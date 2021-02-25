
# let Flux discover the trainable parameters

Flux.@functor RxGate
Flux.@functor RyGate
Flux.@functor RzGate
Flux.@functor RotationGate
Flux.@functor PhaseShiftGate
Flux.@functor ControlledGate
Flux.@functor EntanglementXXGate
Flux.@functor EntanglementYYGate
Flux.@functor EntanglementZZGate
Flux.@functor CircuitGate
Flux.@functor Moment
Flux.@functor MeasurementOperator
Flux.@functor Circuit


function collect_gradients(cx::Zygote.Context, q, dq)
    # special cases: circuit gate chain
    # TODO: also support measurement operators
    if typeof(q) <: AbstractVector{<:AbstractCircuitGate} || typeof(q) <: AbstractVector{<:Moment}
        for i in 1:length(q)
            collect_gradients(cx, q[i], dq[i])
        end
    else
        # need to explicitly "accumulate parameters" for Flux Params([...]) to work
        Zygote.accum_param(cx, q, dq)
        for f in fieldnames(typeof(q))
            try
                collect_gradients(cx, getfield(q, f), getfield(dq, f))
            catch UndefRefError
            end
        end
    end
end


# custom adjoint
Zygote.@adjoint apply(moments::Vector{Moment}, ψ::Vector{<:Complex}) = begin
    N = Qaintessent.intlog2(length(ψ))
    length(ψ) == 2^N || error("Vector length must be a power of 2")
    ψ1 = apply(moments, ψ)
    ψ1, function(Δ)
        # factor 1/2 due to convention for Wirtinger derivative with prefactor 1/2
        dmoments, ψbar = Qaintessent.backward(moments, ψ1, 0.5*Δ, N)
        ψbar .*= 2.0
        collect_gradients(__context__, moments, dmoments)
        return (dmoments, ψbar)
    end
end


# custom adjoint
Zygote.@adjoint apply(c::Circuit{N}, ψ::AbstractVector) where {N} = begin
    apply(c, ψ), function(Δ)
        # TODO: don't recompute apply(c, ψ) here
        dc, ψbar = Qaintessent.gradients(c, ψ, Δ)
        collect_gradients(__context__, c, dc)
        return (dc, ψbar)
    end
end
