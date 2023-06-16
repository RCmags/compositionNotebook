# :question: About 
This repo contains Julia notebooks that convert box diagrams into executable functions.
Different scenarios are explored, but focus is placed on assigning ordinary differential equations to the boxes. 
Each box corresponds to a set of ODE's and the wires between them determine how they communicate.

## :star2: Production release
See [AlgebraicContracts.jl](https://github.com/bakirtzisg/AlgebraicContracts.jl) to download the Julia Package. Massive thanks for Georgios Bakirtzis and Cody Fleming for helping me on this project.

## :scroll: Papers
This is work is motivated by the following papers:

1. _Georgios Bakirtzis, Cody H. Fleming, and Christina Vasilakopoulou_  
["Compositional Cyber-Physical Systems Modeling"](https://arxiv.org/abs/2101.10484)   

2. _Georgios Bakirtzis, Cody H. Fleming, and Christina Vasilakopoulou_  
["Categorical Semantics of Cyber-Physical Systems Theory"](https://arxiv.org/abs/2010.08003)

## :bomb: Requirements
To run the notebooks you will require the following packages:
- [Catlab](https://juliapackages.com/p/catlab)
- [AlgebraicDynamics](https://juliapackages.com/packages/algebraicdynamics)
- [DifferentialEquations](https://juliapackages.com/p/differentialequations)
- [Plots](https://juliapackages.com/p/plots)

You will also need to install graphviz:
- [Graphviz](https://graphviz.org)

See "requirement.txt" for the nessesary versions along with the version of Julia used to write the notebooks. 
Other versions will work but the given versions are sure to compile. 

## :dvd: Installation
Open REPL and press ] so the console shows pkg> then type:  

```
add Catlab@0.11.2
add AlgebraicDynamics@0.1.2
add DifferentialEquations@6.17.1
add Plots@1.16.3
```  

To install Graphviz on Windows simply download the executable: [Graphviz 2.47.2 for Windows 10 (64-bit)](https://gitlab.com/api/v4/projects/4207231/packages/generic/graphviz-releases/2.47.2/stable_windows_10_cmake_Release_x64_graphviz-install-2.47.2-win64.exe)


__NOTE__: Installing packages on Windows can be very slow. 
To prevent this, open Windows Defender and go to Virus & Threat protection settings. Dissable real-time protection. 
You can enable it once the packages are installed.
