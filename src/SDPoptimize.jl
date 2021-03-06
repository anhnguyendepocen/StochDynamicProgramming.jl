#  Copyright 2015, Vincent Leclere, Francois Pacaud, Henri Gerard and
#  Tristan Rigaut
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.
#############################################################################
#  Stochastic dynamic programming algorithm
#
#############################################################################

using ProgressMeter
using Iterators
using Interpolations


"""
Compute interpolation of the value function at time t

# Arguments
* `model::SPmodel`:
* `dim_states::Int`:
    the number of state variables
* `v::Array`:
    the value function to interpolate
* `time::Int`:
    time at which we have to interpolate V

# Return
* Interpolation
    the interpolated value function (working as an array with float indexes)

"""
function value_function_interpolation( dim_states, V, time::Int)
    return interpolate(V[[Colon() for i in 1:dim_states]...,time], BSpline(Linear()), OnGrid())
end


"""
Compute the cartesian products of discretized state and control spaces

# Arguments
* `model::SPmodel`:
    the model of the problem
* `param::SDPparameters`:
    the parameters of the problem

# Return
* Iterators: product_states and product_controls
    the cartesian product iterators for both states and controls

"""
function generate_grid(model::SPModel, param::SDPparameters)
    product_states = product([model.xlim[i][1]:param.stateSteps[i]:model.xlim[i][2] for i in 1:model.dimStates]...)
    product_controls = product([model.ulim[i][1]:param.controlSteps[i]:model.ulim[i][2] for i in 1:model.dimControls]...)
    return product_states, product_controls
end


"""
Transform a general SPmodel into a StochDynProgModel

# Arguments
* `model::SPmodel`:
    the model of the problem
* `param::SDPparameters`:
    the parameters of the problem

# Return
* `sdpmodel::StochDynProgModel:
    the corresponding StochDynProgModel

"""
function build_sdpmodel_from_spmodel(model::SPModel)

    function zero_fun(x)
        return 0
    end

    if isa(model,LinearSPModel)
        function cons_fun(t,x,u,w)
            return true
        end
        if in(:finalCostFunction,fieldnames(model))
            SDPmodel = StochDynProgModel(model, model.finalCostFunction, cons_fun)
        else
            SDPmodel = StochDynProgModel(model, zero_fun, cons_fun)
        end
    elseif isa(model,StochDynProgModel)
        SDPmodel = model
    else
        error("cannot build StochDynProgModel from current SPmodel. You need to implement
        a new StochDynProgModel constructor.")
    end

    return SDPmodel
end


"""
Dynamic programming algorithm to compute optimal value functions
by backward induction using bellman equation in the finite horizon case.
The information structure can be Decision Hazard (DH) or Hazard Decision (HD)

# Arguments
* `model::SPmodel`:
    the DPSPmodel of our problem
* `param::SDPparameters`:
    the parameters for the SDP algorithm
* `display::Int`:
    the output display or verbosity parameter

# Return
* `value_functions::Array`:
    the vector representing the value functions as functions of the state
    of the system at each time step

"""
function solve_DP(model::SPModel, param::SDPparameters, display=0::Int64)
    SDPmodel = build_sdpmodel_from_spmodel(model::SPModel)
    # Start of the algorithm
    V = sdp_compute_value_functions(SDPmodel, param, display)
    return V
end


"""
Compute the value function at time t using bellman equation
and knowing value function at time t+1

# Parameters
* `sampling::iz`: (Int)
    number of noises samples (number of outcomes if the probability laws are discrete,
    number of monte carlo samples otherwise)
* `samples::Array{Float64}`:
    arrays of the noises samples/realizations
* `probas::Array{Float64}`:
    array of probabilities of samples
* `u_bounds::Array{Tuple{Float64}}`:
    array of lower and upper bounds of controls
* `x_bounds::Array{Tuple{Float64}}`:
    array of lower and upper bounds of states
* `x_steps::Array{Float64}`:
    array of discretization steps for states space
* `x_dim::Int`:
    number of state variables
* `product_states::Array{Float64}`:
    discretized state space
* `product_controls::Array{Float64}`:
    discretized control space
* `dynamics::Function`:
    dynamics function of the time step, state, control and randomness returning next state
* `contraints::Function`:
    constraints function of the time step, state, control and randomness returning boolean
* `cost::Function`:
    cost function of the time step, state, control and randomness returning the instantaneous cost
* `V::Array or SharedArray`:
    the array containing the discretized value functions at each time step
* `Vitp::Interpolations`:
    the interpolated value functions
* `t::Float64`:
    the time step
* `info_struc::String`:
    the information structure "HD" for hazard-decision
    or "DH" for decision-hazard

"""
function compute_V_given_t(sampling_size, samples, probas, u_bounds, x_bounds,
                                x_steps, x_dim, product_states, product_controls,
                                dynamics, constraints, cost, V, Vitp, t, info_struc)

    if info_struc == "DH"
        @sync @parallel for indx in 1:length(product_states)
            SDPutils.compute_V_given_x_t_DH(sampling_size, samples,
                                            probas, u_bounds, x_bounds,
                                            x_steps, x_dim, product_controls,
                                            dynamics, constraints, cost, V, Vitp,
                                            t, product_states[indx])
        end
    elseif info_struc == "HD"
        @sync @parallel for indx in 1:length(product_states)
            SDPutils.compute_V_given_x_t_HD(sampling_size, samples, probas,
                                            u_bounds, x_bounds, x_steps, x_dim,
                                            product_controls, dynamics,
                                            constraints, cost, V, Vitp,
                                            t, product_states[indx])
        end
    else
        error("Information structure should be HD or DH")
    end
end


"""
Dynamic Programming algorithm to compute optimal value functions

# Parameters
* `model::StochDynProgModel`:
    the StochDynProgModel of the problem
* `param::SDPparameters`:
    the parameters for the algorithm
* `display::Int`:
    the output display or verbosity parameter

# Returns
* `value_functions::Array`:
    the vector representing the value functions as functions of the state
    of the system at each time step

"""
function sdp_compute_value_functions(model::StochDynProgModel,
                                     param::SDPparameters,
                                     display=0::Int64)

    TF = model.stageNumber
    next_state = zeros(Float64, model.dimStates)

    u_bounds = model.ulim
    x_bounds = model.xlim
    x_steps = param.stateSteps
    x_dim = model.dimStates

    dynamics = model.dynamics
    constraints = model.constraints
    cost = model.costFunctions

    law = model.noises

    #Compute cartesian product spaces
    product_states, product_controls = generate_grid(model, param)

    product_states = collect(product_states)
    product_controls = collect(product_controls)

    V = SharedArray{Float64}(zeros(Float64, param.stateVariablesSizes..., TF))

    #Compute final value functions
    for x in product_states
        ind_x = SDPutils.index_from_variable(x, x_bounds, x_steps)
        V[ind_x..., TF] = model.finalCostFunction(x)
    end

    if param.expectation_computation!="MonteCarlo" && param.expectation_computation!="Exact"
        warn("param.expectation_computation should be 'MonteCarlo' or 'Exact'. Defaulted to 'exact'")
        param.expectation_computation="Exact"
    end

    #Construct a progress meter
    p = 0
    if display > 0
        p = Progress((TF-1), 1)
        println("[SDP] Starting value functions computation:")
    end

    # Loop over time:
    for t = (TF-1):-1:1

        if display > 0
            next!(p)
        end

        if (param.expectation_computation=="MonteCarlo")
            sampling_size = param.monteCarloSize
            samples = [sampling(law,t) for i in 1:sampling_size]
            probas = (1/sampling_size)
        else
            sampling_size = law[t].supportSize
            samples = law[t].support
            probas = law[t].proba
        end

        Vitp = value_function_interpolation(x_dim, V, t+1)

        compute_V_given_t(sampling_size, samples, probas, u_bounds, x_bounds,
                                x_steps, x_dim, product_states, product_controls,
                                dynamics, constraints, cost, V, Vitp, t
                                , param.infoStructure)

    end
    return V
end


"""
Get the optimal value of the problem from the optimal Bellman Function

# Arguments
* `model::SPmodel`:
    the DPSPmodel of our problem
* `param::SDPparameters`:
    the parameters for the SDP algorithm
* `V::Array{Float64}`:
    the Bellman Functions

# Return
* `V_x0::Float64`:

"""
function get_bellman_value(model::SPModel, param::SDPparameters, V)
    ind_x0 = SDPutils.real_index_from_variable(model.initialState, model.xlim, param.stateSteps)
    Vi = value_function_interpolation(model.dimStates, V, 1)
    return Vi[ind_x0...,1]
end


"""
Simulation of optimal trajectories given model and Bellman functions

# Arguments
* `model::SPmodel`:
    the SPmodel of our problem
* `param::SDPparameters`:
    the parameters for the SDP algorithm
* `scenarios::Array`:
    the scenarios of uncertainties realizations we want to simulate on
    scenarios[t,k,:] is the alea at time t for scenario k
* `V::Array`:
    the vector representing the value functions as functions of the state
    of the system at each time step
* `display::Bool`:
    the output display or verbosity parameter

# Return
* `costs::Vector{Float64}`:
    the cost of the optimal control over the scenario provided
* `states::Array{Float64}`:
    the state of the controlled system at each time step
* `controls::Array{Float64}`:
    the controls applied to the system at each time step

"""
function sdp_forward_simulation(model::SPModel, param::SDPparameters,
                                scenarios::Array{Float64,3},
                                V,
                                display=false::Bool)

    SDPmodel = build_sdpmodel_from_spmodel(model)
    TF = SDPmodel.stageNumber
    nb_scenarios = size(scenarios)[2]

    costs = zeros(nb_scenarios)
    states = zeros(TF,nb_scenarios,model.dimStates)
    controls = zeros(TF-1,nb_scenarios,model.dimControls)


    for k = 1:nb_scenarios
        costs[k], states[:,k,:], controls[:,k,:] = sdp_forward_single_simulation(SDPmodel,
                  param,scenarios[:,k,:],model.initialState,V,display)
    end

    return costs, states, controls
end


"""
Get the optimal control at time t knowing the state of the system in the decision hazard case

# Arguments
* `model::SPmodel`:
    the DPSPmodel of our problem
* `param::SDPparameters`:
    the parameters for the SDP algorithm
* `V::Array{Float64}`:
    the Bellman Functions
* `t::int`:
    the time step
* `x::Array`:
    the state variable
* `w::Array`:
    the alea realization

# Return
* `V_x0::Float64`:

"""
function get_control(model::SPModel,param::SDPparameters,V, t::Int64, x::Array)

    if(param.infoStructure != "DH")
        error("Infostructure must be decision-hazard.")
    end
    SDPmodel = build_sdpmodel_from_spmodel(model)

    product_controls = product([SDPmodel.ulim[i][1]:param.controlSteps[i]:SDPmodel.ulim[i][2] for i in 1:SDPmodel.dimControls]...)

    law = SDPmodel.noises
    best_control = tuple()
    Vitp = value_function_interpolation(SDPmodel.dimStates, V, t+1)

    u_bounds = SDPmodel.ulim
    x_bounds = SDPmodel.xlim
    x_steps = param.stateSteps

    best_V = Inf

    for u in product_controls

        count_admissible_w = 0.
        current_V = 0.

        if (param.expectation_computation=="MonteCarlo")
            sampling_size = param.monteCarloSize
            samples = [sampling(law,t) for i in 1:sampling_size]
            probas = (1/sampling_size)
        else
            sampling_size = law[t].supportSize
            samples = law[t].support
            probas = law[t].proba
        end

        for w = 1:sampling_size

            w_sample = samples[:, w]
            proba = probas[w]

            next_state = SDPmodel.dynamics(t, x, u, w_sample)

            if SDPmodel.constraints(t, x, u, w_sample)&&SDPutils.is_next_state_feasible(next_state, model.dimStates, model.xlim)
                ind_next_state = SDPutils.real_index_from_variable(next_state, x_bounds, x_steps)
                next_V = Vitp[ind_next_state...]
                current_V += proba *(SDPmodel.costFunctions(t, x, u, w_sample) + next_V)
                count_admissible_w = count_admissible_w + proba
            end
        end
        current_V = current_V/count_admissible_w
        if (current_V < best_V)&(count_admissible_w>0)
            best_control = u
            best_V = current_V
        end
    end

    return best_control
end


"""
Get the optimal control at time t knowing the state of the system and the alea in the hazard decision case

# Arguments
* `model::SPmodel`:
    the DPSPmodel of our problem
* `param::SDPparameters`:
    the parameters for the SDP algorithm
* `V::Array{Float64}`:
    the Bellman Functions
* `t::int`:
    the time step
* `x::Array`:
    the state variable
* `w::Array`:
    the alea realization

# Return
* optimal control (tuple(Float64))

"""
function get_control(model::SPModel,param::SDPparameters,V, t::Int64, x::Array, w::Array)

    if(param.infoStructure != "HD")
        error("Infostructure must be hazard-decision.")
    end

    SDPmodel = build_sdpmodel_from_spmodel(model)

    product_controls = product([SDPmodel.ulim[i][1]:param.controlSteps[i]:SDPmodel.ulim[i][2] for i in 1:SDPmodel.dimControls]...)

    law = SDPmodel.noises
    best_control = tuple()
    Vitp = value_function_interpolation(SDPmodel.dimStates, V, t+1)

    u_bounds = SDPmodel.ulim
    x_bounds = SDPmodel.xlim
    x_steps = param.stateSteps

    best_V = Inf

    for u = product_controls

        next_state = SDPmodel.dynamics(t, x, u, w)

        if SDPmodel.constraints(t, x, u, w)&&SDPutils.is_next_state_feasible(next_state, model.dimStates, model.xlim)
            ind_next_state = SDPutils.real_index_from_variable(next_state, x_bounds, x_steps)
            next_V = Vitp[ind_next_state...]
            current_V = SDPmodel.costFunctions(t, x, u, w) + next_V
            if (current_V < best_V)
                best_control = u
                best_state = SDPmodel.dynamics(t, x, u, w)
                best_V = current_V
            end
        end

    end

    return best_control

end


"""
Simulation of optimal control given an initial state and an alea scenario

# Arguments
* `model::SPmodel`:
    the DPSPmodel of our problem
* `param::SDPparameters`:
    the parameters for the SDP algorithm
* `scenario::Array`:
    the scenario of uncertainties realizations we want to simulate on
* `X0::SDPparameters`:
    the initial state of the system
* `V::Array`:
    the vector representing the value functions as functions of the state
    of the system at each time step
* `display::Bool`:
    the output display or verbosity parameter

# Return
* `J::Float`:
    the cost of the optimal control over the scenario provided
* `stocks::Array`:
    the state of the controlled system at each time step
* `controls::Array`:
    the controls applied to the system at each time step
"""
function sdp_forward_single_simulation(model::StochDynProgModel,
                                        param::SDPparameters,
                                        scenario::Array,
                                        X0::Array,
                                        V,
                                        display=true::Bool)

    if VERSION.minor < 5
        scenario = reshape(scenario, size(scenario, 1), size(scenario, 3))
    end
    TF = model.stageNumber
    law = model.noises
    u_bounds = model.ulim
    x_bounds = model.xlim
    x_steps = param.stateSteps

    #Compute cartesian product spaces
    p_states, p_controls = generate_grid(model, param)
    product_states = collect(p_states)
    product_controls = collect(p_controls)

    product_states = collect(product_states)
    product_controls = collect(product_controls)

    controls = Inf*ones(TF-1, 1, model.dimControls)
    states = Inf*ones(TF, 1, model.dimStates)

    state_num = 0
    for xj in X0
        state_num += 1
        states[1, 1, state_num] = xj
    end

    J = 0
    best_state = X0

    best_control = tuple()

    if (param.infoStructure == "DH")
        #Decision hazard forward simulation
        for t = 1:(TF-1)

            x = states[t,1,:]

            best_V = Inf
            Vitp = value_function_interpolation(model.dimStates, V, t+1)

            for u in product_controls

                count_admissible_w = 0.
                current_V = 0.

                if (param.expectation_computation=="MonteCarlo")
                    sampling_size = param.monteCarloSize
                    samples = [sampling(law,t) for i in 1:sampling_size]
                    probas = (1/sampling_size)
                else
                    sampling_size = law[t].supportSize
                    samples = law[t].support
                    probas = law[t].proba
                end

                for w = 1:sampling_size

                    w_sample = samples[:, w]
                    proba = probas[w]

                    next_state = model.dynamics(t, x, u, w_sample)

                    if model.constraints(t, x, u, w_sample)&&SDPutils.is_next_state_feasible(next_state, model.dimStates, model.xlim)
                        ind_next_state = SDPutils.real_index_from_variable(next_state, x_bounds, x_steps)
                        next_V = Vitp[ind_next_state...]
                        current_V += proba *(model.costFunctions(t, x, u, w_sample) + next_V)
                        count_admissible_w = count_admissible_w + proba
                    end
                end
                current_V = current_V/count_admissible_w
                if (current_V < best_V)&(count_admissible_w>0)
                    best_control = u
                    best_state = model.dynamics(t, x, u, scenario[t,:])
                    best_V = current_V
                end
            end

            index_control = 0
            for uj in best_control
                index_control += 1
                controls[t,1,index_control] = uj
            end

            index_state = 0
            for xj in best_state
                index_state = index_state +1
                states[t+1,1,index_state] = xj
            end
            J += model.costFunctions(t, x, best_control, scenario[t,:])
        end

    else
        #Hazard desision forward simulation
        for t = 1:TF-1

            x = states[t,1,:]

            Vitp = value_function_interpolation(model.dimStates, V, t+1)

            best_V = Inf

            for u = product_controls

                next_state = model.dynamics(t, x, u, scenario[t,:])

                if model.constraints(t, x, u, scenario[t])&&SDPutils.is_next_state_feasible(next_state, model.dimStates, model.xlim)
                    ind_next_state = SDPutils.real_index_from_variable(next_state, x_bounds, x_steps)
                    next_V = Vitp[ind_next_state...]
                    current_V = model.costFunctions(t, x, u, scenario[t,:]) + next_V
                    if (current_V < best_V)
                        best_control = u
                        best_state = model.dynamics(t, x, u, scenario[t,:])
                        best_V = current_V
                    end
                end

            end
            index_control = 0
            for uj in best_control
                index_control += 1
                controls[t,1,index_control] = uj
            end

            index_state = 0
            for xj in best_state
                index_state = index_state +1
                states[t+1,1,index_state] = xj
            end
            J += model.costFunctions(t, x, best_control, scenario[t,:])
        end
    end

    x = states[TF,1,:]
    J = J + model.finalCostFunction(x)

    return J, states, controls
end

