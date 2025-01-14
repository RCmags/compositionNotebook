module StaticContract

#-- Required modules
using DifferentialEquations
using AlgebraicDynamics
using AlgebraicDynamics.DWDDynam
using Catlab.WiringDiagrams
using IntervalSets
using PrettyTables
using Printf

#-- datatypes used by contract machine
const ContractOutputTable = Dict{KEY, NamedTuple{ (:input, :output), 
                                                    Tuple{ Vector{ Pair{Symbol, Bool} }, 
                                                            Vector{ Pair{Symbol, Bool} } } } 
                                } where KEY <: Union{Symbol, Any}

const ContractTimeTable = Dict{Any, Any}

const ContractOutputBox = NamedTuple{ (:input, :output), 
                                    Tuple{ Vector{Bool}, Vector{Bool} } }

#-- Type to display pretty table
struct ContractTable
    table::Union{ContractOutputTable, ContractTimeTable, ContractOutputBox} 
end

#-- Contracts are defined via intervals
struct ContractMachine{T<:Real}
    cinput::Vector{Interval}
    coutput::Vector{Interval}  
    machine::AbstractMachine{T}
    fcontract::Function  
    
    # inner constructor
    function ContractMachine{T}(cinput::Vector, coutput::Vector, machine::AbstractMachine{T}; 
                                fcontract = nothing) where T<:Real
        # cannot have empty contract
        for contract in [cinput; coutput]
            if isempty(contract)
                error("the interval $c is backwards")
            end
        end
                
        # contract function 
        if fcontract == nothing     # Only define function in none is provided, used to not overwrite the composed function from oapply
            fcontract = (u::AbstractVector, x::AbstractVector, p=nothing, t=0) -> begin
                Rin = map( (xin,cont) -> xin in cont, x, cinput )                           # check whether contracts at input ports are satisfied
                Rout = map( (rout,cont) -> rout in cont, readout(machine)(u, p, t), coutput )      # check whether contracts at output ports are satisfied
                return ContractTable( (input = Rin, output = Rout) )
            end
        end
        # make a new machine satisfying these restrictions
        new{T}(cinput, coutput, machine, fcontract)
    end
end

# outer constructor
function ContractMachine{T}(cinput::Vector, nstates::Int, coutput::Vector, dynamics::Function, readout::Function; 
                            fcontract = nothing, mtype = :continuous) where T<:Real
    # each element in the vectors is a contract for the port on a box
    ninputs = length(cinput)
    noutputs = length(coutput)
    
    # select a machine type
    if mtype == :continuous
        machine = ContinuousMachine{T}(ninputs, nstates, noutputs, dynamics, readout)
    elseif mtype :discrete
        machine = DiscreteMachine{T}(ninputs, nstates, noutputs, dynamics, readout)
    end
    # make a machine using inner constructor
    ContractMachine{T}(cinput, coutput, machine, fcontract=fcontract )
end

#-- Compose multiple contract machines --

function DWDDynam.oapply(d::WiringDiagram, ms::Vector{ContractMachine{T}}) where T<:Real
    # ensure there is one machine for each box in the diagram
    if nboxes(d) != length(ms)
        error("there are $nboxes(d) boxes but $length(ms) machines")
    end
    
    # store the name of the wires going entering and exiting each box
    input_port = Array{Vector}(undef, nboxes(d))
    output_port  = Array{Vector}(undef, nboxes(d))
    
    for id in 1:nboxes(d)
        input_port[id] = input_ports(d, id)
        output_port[id] = output_ports(d, id)
        
        # ensure each wire is assigned a contract interval
        if ( length(input_port[id]) != ninputs(ms[id].machine) || 
             length(output_port[id]) != noutputs(ms[id].machine) )
            error("number of ports do not match number of contracts at box $id")
        end
    end
    
    # check all of the wires inside the diagram (these exclude wires that enter or exit the diagram)
    boxs = boxes(d)     # boxes in diagram
    
    for w in wires(d, :Wire)   
        # ensure target and source name match. See Categorical Semantics p.16
        t_var = boxs[w.target.box].input_ports[w.target.port]
        s_var = boxs[w.source.box].output_ports[w.source.port]
            
        if t_var != s_var
            error("variable names do not match at $w")
        end
        
        # the name of the source and target box
        s_name = boxs[w.source.box].value
        t_name = boxs[w.target.box].value
        
        # check whether the output contract of the source is compatible with the input contract of the target
        cout = ms[w.source.box].coutput[w.source.port]
        cin = ms[w.target.box].cinput[w.target.port]
        overlap = intersect(cout, cin)

        if isempty(overlap) == true
            error("the contract $cout of $s_name does not satisfy the contract $cin of $t_name at wire $t_var")
        elseif overlap != cout
            @warn("contract $cout of $s_name is undefined at the contract $cin of $t_name at wire $t_var")
        end
    end
    
    # store the contracts of the wires entering and exiting the digram
    cinput = map(w -> ms[w.target.box].cinput[w.target.port], wires(d, :InWire))
    coutput = map(w -> ms[w.source.box].coutput[w.source.port], wires(d, :OutWire))
    
    # get the initial index of the state vector of each each box. The composition concatenates these vectors into a single column.
    nstate = 0
    index = Array{UnitRange{Int}}(undef, nboxes(d))
    
    for i in 1:nboxes(d)
        nstate += nstates(ms[i].machine)                           # initial index of vector
        index[i] = nstate - nstates(ms[i].machine) + 1 : nstate    # store vector indeces
    end
    
    # get the name of each box
    name = map( box -> box.value, boxes(d) )
    
    #---- Evaluate contracts           
    function fcontract(u::AbstractVector, x::AbstractVector, p=nothing, t=0) 
        # get the output of each box
        rout = map( id -> readout(ms[id].machine)( u[index[id]], p, t ), 1:nboxes(d) ) # readout function needs to accept time and parameters.
        
        # evaluate the contract function
        fout = Array{Dict}(undef, nboxes(d))
        
        for id in 1:nboxes(d)                       # check all boxes in the diagram
            # collect the inputs of each box
            xin = zeros( ninputs(ms[id].machine) )    
            
            for w in in_wires(d, id)                # check all wires going into a box
                if w.source.box != input_id(d)      # iternal inputs use are the readout of another box
                    xin[w.target.port] += rout[w.source.box][w.source.port]  
                else                                # external inputs make use of a given vector
                    xin[w.target.port] += x[w.source.port] 
                end
            end
            
            # evaluate the contract function of each box
            param = p == nothing ? nothing : p[index[id]] 
            foutput = ms[id].fcontract( u[index[id]], xin, param, t ).table
            
            # for atomic boxes, assign the box name to the inputs and outputs
            if typeof(foutput) <: NamedTuple
                fout[id] = Dict(name[id] => (input = input_port[id] .=> foutput.input, 
                                              output = output_port[id] .=> foutput.output))
            else    # for nested boxes, append the name of the parent box to the child boxes 
                fout[id] = Dict( (name[id] .=> keys(foutput)) .=> values(foutput) )
            end
        end
        # return a contract table with a box directory assigned to inputs and outputs
        return ContractTable( merge(fout...) )
    end
    
    # compose the dynamics functions
    machine = DWDDynam.oapply(d, map(m -> m.machine, ms))
    
    # return the composed machine
    return ContractMachine{T}(cinput, coutput, machine, fcontract=fcontract)
end

#---------

# Identify during which time intervals a signal is zero [false == contract is violated]
function failureInterval(arr::AbstractVector, time = nothing)
    # check each element in the array
    index = Array{Tuple}(undef, 0) 
    start = 1   

    for i in 1:length(arr)             # no previous element
        if i != 1 
            if arr[i] > arr[i-1]       # rising signal 
                push!( index, (start, i-1) )

            elseif arr[i] < arr[i-1]   # falling signal 
                start = i 
            end 
        
            if i == length(arr) && arr[end] <= 0   # end of interval
                push!( index, (start, i) )
            end
        end
    end
    
    # map indeces to given array 
    if time != nothing
        index = map( set -> (time[set[1]], time[set[2]]), index)
    end
    
    # output 2d array of start and stop times
    return index
end

# Assign contract failure times to each wire of each box
function check_contract(sol::T1, machine::ContractMachine{T2}, x0::AbstractVector) where {T1<:ODESolution, T2<:Real}
    
    # evalutate the contract function throughout time interval 
    fout = map( t -> machine.fcontract(sol(t), x0), sol.t )
    
    # store time at which each contract fails for each box directory
    set0 = fout[begin].table	# Initial evaluation of contracts. Used to get the names and wires of each box.
    dict = Dict()    
    
    for key in keys(set0)   # go through all directories
	
        mapOut = index -> map(i -> set0[key][index][i].first => begin 
                contract = map(set -> set.table[key][index][i].second, fout);    # array of the contract state for each time step
                failureInterval(contract, sol.t);                                 # find the duration of 0's in the array
            end, 1:length( set0[key][index] ) )
        
        dict[key] = ( input=mapOut(:input), output=mapOut(:output) )    # store the times at the directory
    end
    
    # output a data structure like that of fcontract but with failure intervals.
    return ContractTable(dict), fout
end

#-- Pretty printing of output

# display contract machines as product of intervals
function Base.show(io::IO, vf::ContractMachine)            
    # Check all contracts
    list = [vf.cinput; vf.coutput]
    output = ""
    
    for contract in list
        if -contract.left == contract.right == Inf
            output *= "ℝ"
        else
            left = contract.left == -Inf ? "-∞" : contract.left
            right = contract.right == Inf ? "∞"  : contract.right
            output *= "[$left,$right]"
        end
        if contract != last(list) # fix for R x R
            output *= " × "
        end
    end  
    
    # display combined string
    print("ContractMachine( "*output*" )")
end

# display contract tables (output of fcontract and eval_contract) as a pretty table
function Base.show(io::IO, data::ContractTable)
    # get the data structure
    dict = data.table
    
    # select the appriate table
    if typeof(dict) <: ContractOutputBox        # atomic box
        # assign a contract state to each port 
        mapOut = index -> join( string.(1:length(dict[index])) .* " : " .* string.(dict[index]), "\n" )
        
        # do not assign a box as there is no diagram
        output = hcat( [mapOut(:input)], [mapOut(:output)] )
        header = ( ["input", "output"], ["port: contract", "port: contract"] )
    
    else # composed boxes
        box = string.(keys(dict))
        
        if typeof(dict) <: ContractOutputTable  # output of fcontract
            mapOut = index -> map( x -> join( map(pair -> string(pair.first) * " : " * string(pair.second), x[index]), "\n"), values(dict) )
            
            header =  ( ["box", "input", "output"], ["directory", "wire: contract", "wire: contract"] )
        
        else    # output of eval_contract
            mapOut = index -> map( value -> begin # make a large string of time intervals (with bounds in scientific notation) for each box directory
                                    out = map( pair -> map( set -> @sprintf("%s : %.2e , %.2e", pair.first, set...), pair.second ), value[index]);
                                    join( vcat(out...), "\n") 
                        end, values(dict) )
                        
            header = ( ["box", "input", "output"], ["directory", "wire: failure interval", "wire: failure interval"] ) 
        end
        # both types have the same structure
        output = hcat(box, mapOut(:input), mapOut(:output))
    end
    # display a pretty table
    pretty_table(output, header = header, backend=:html, linebreaks=true, tf=tf_html_minimalist, alignment=:c)
end

#-- helper functions

# compose machines given the name of each box
function DWDDynam.oapply(d::WiringDiagram, ms::Dict{Symbol, ContractMachine{T}}) where T<:Real
    oapply(d, map(box -> ms[box.value], boxes(d)) )
end

# solve the dynamics of the contract machines
function DWDDynam.ODEProblem(m::ContractMachine{T}, u0::AbstractVector, xs::AbstractVector, tspan::Tuple, p=nothing) where T<:Real
    DWDDynam.ODEProblem(m.machine, u0, xs, tspan, p)
end

#-- Information accesible by using module
export ContractTable, ContractMachine, oapply, failureInterval, check_contract, ODEProblem

end

#NOTE: the contracts need to change with time. That is, they must be functions with respect to time. Modify base contract function.