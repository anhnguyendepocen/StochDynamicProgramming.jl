using Base.Meta

state_names = []
control_names = []
aleas_names = []

function SPModel(str_type)
    if str_type == "Linear"
        return(LinearDynamicLinearCostSPmodel())
    elseif str_type == "PiecewiseLinear"
        return(PiecewiseLinearCostSPmodel())
    else
        return(StochDynProgModel())
    end
end

macro addState(model, arg...)
    push!(state_names, arg[1].args[3].args[1]);
    esc(quote
            push!($(model).xlim, ($(arg[1].args[1]),$(arg[1].args[5])));
            $(model).dimStates += 1;
            $(model).stageNumber = $(arg[1].args[3].args[2].args[2]);
        end)
end

macro addControl(model, arg...)
    push!(control_names, arg[1].args[3].args[1]);
    esc(quote
            push!($(model).ulim, ($(arg[1].args[1]),$(arg[1].args[5])));
            $(model).dimControls += 1;
        end)
end

macro addStochVariable(model, arg...)
    #TODO : Multidimensional case!!!
    push!(aleas_names, arg[1]);
    esc(quote
            $(model).noises = NoiseLaw[NoiseLaw($(arg[1])[t][2,:], $(arg[1])[t][1,:]) for t in 1:N_STAGES-1];
            $(model).dimNoises += 1;
        end)
end

macro setStochObjective(model, ope, arg...)
    #TODO : almost everything, Max, finalCostFunction, prevent case where a variable name is at the end of another one...
    #Better way to handle this part?
    if ope == :Min
        ind = find(arg[1].args .== :sum)[1]
        costExpr = string(arg[1].args[ind+1])
        for i in length(state_names)
            costExpr = replace(costExpr, string(string(state_names[i]),"[i]"),string("x"string([i])))
        end
        for i in length(control_names)
            costExpr = replace(costExpr, string(string(control_names[i]),"[i]"),string("u"string([i])))
        end
        for i in length(aleas_names)
            costExpr = replace(costExpr, string(string(aleas_names[i]),"[i]"),string("w"string([i])))
        end
        costExpr = parse(costExpr)
        esc(quote
            function cost_t(i,x,u,w)
                return($costExpr)
            end
            $(model).costFunctions = cost_t
        end)

    elseif ope == :Max

    else
        #@error("Missing min or max")
    end
end

macro addDynamic(model, arg...)
        #TODO : almost everything, Multidimensional case (more than 1 dynamic => we should not redefine the function)
        #IMO Macros will be particularly relevent in this case
        dynamicExpr = string(arg[1])
        for i in length(state_names)
            dynamicExpr = replace(dynamicExpr, string(string(state_names[i]),"[i]"),string("x"string([i])))
        end
        for i in length(control_names)
            dynamicExpr = replace(dynamicExpr, string(string(control_names[i]),"[i]"),string("u"string([i])))
        end
        for i in length(aleas_names)
            dynamicExpr = replace(dynamicExpr, string(string(aleas_names[i]),"[i]"),string("w"string([i])))
        end
        dynamicExpr = parse(dynamicExpr)
        esc(quote
            function dyn_t(i,x,u,w)
                return($dynamicExpr)
            end
            $(model).dynamics = dyn_t
        end)
end

macro addConstraintsdp(model, arg...)
        if (match(r"\[1]",string(arg[1])) == nothing)
            1+1
        else
            esc(quote
                    $(model).initialState = [$(arg[1].args[3])]
                end
                )
        end
end

function solveInterface(model::SPModel, strSDP, strHD, stateDisc, controlDisc, solver)
    if strSDP== "SDP"
        if strHD=="HD"
            paramSDP = SDPparameters(model, stateDisc, controlDisc, strHD)
            Vs = sdp_optimize(model,paramSDP)
            lb_sdp = get_value(model,paramSDP,Vs)
            println("Value obtained by SDP: "*string(lb_sdp))
        end
    end
end