# StochDynamicProgramming


**WARNING:** *This package is currently in development. Any help or feedback is appreciated.*


**Latest release:** 0.1.3


[![Build Status](https://travis-ci.org/JuliaOpt/StochDynamicProgramming.jl.svg?branch=master)](https://travis-ci.org/JuliaOpt/StochDynamicProgramming.jl)
[![codecov.io](https://codecov.io/github/JuliaOpt/StochDynamicProgramming.jl/coverage.svg?branch=master)](https://codecov.io/github/JuliaOpt/StochDynamicProgramming.jl?branch=master)


This is a Julia package for optimizing controlled stochastic dynamic system (in discrete time). It offers three methods of resolution :

- *Extensive formulation*.
- *Stochastic Dynamic Programming*.
- *Stochastic Dual Dynamic Programming* (SDDP) algorithm.

It is built upon [JuMP](https://github.com/JuliaOpt/JuMP.jl)

## What problem can we solve with this package ?

- Stage-wise independent discrete noise
- Linear dynamics
- Linear or convex piecewise linear cost

Extension to non-linear formulation are under development. 
Extension to more complex alea dependance are under developpment.

## Why Extensive formulation ?

An extensive formulation approach consists in representing the stochastic problem as a deterministic
one with more variable and call a standard deterministic solver. Mainly usable in a linear 
setting. Computational complexity is exponential in the number of stages.

## Why Stochastic Dynamic Programming ?

Dynamic Programming is a standard tool to solve stochastic optimal control problem with
independent noise. The method require discretisation of the state space, and is exponential
in the dimension of the state space.

## Why SDDP?

SDDP is a dynamic programming algorithm relying on cutting planes. The algorithm require convexity
of the value function but does not discretize the state space. The complexity is linear in the
number of stage, and can accomodate higher dimension state than standard dynamic programming.
The algorithm return exact lower bound and estimated upper bound as well as approximate optimal
control strategies.



## Installation
Installing StochDynamicProgramming is an easy process. Open Julia and enter

```julia
julia> Pkg.update()
julia> Pkg.add("StochDynamicProgramming")

```


## Usage

IJulia Notebooks will be provided to explain how this package work.
A first example on a two dams valley [here.] (http://nbviewer.jupyter.org/github/leclere/StochDP-notebooks/blob/master/notebooks/damsvalley.ipynb)


## Documentation

The documentation is built with Sphinx, so ensure that this package is installed:

```bash
sudo apt-get install python-sphinx

```

To build the documentation:

```bash
cd doc
make html

```

## License

Released under Mozilla Public License (see LICENSE.md for further details).
