using Test
using TestSetExtensions
using LinearAlgebra
using Flux
using Qaintellect


# adapted from https://github.com/FluxML/Zygote.jl/blob/master/test/gradcheck.jl
function ngradient(f, xs::AbstractArray...)
    grads = zero.(xs)
    for (x, Δ) in zip(xs, grads), i in 1:length(x)
        δ = sqrt(eps())
        tmp = x[i]
        x[i] = tmp - δ/2
        y1 = f(xs...)
        x[i] = tmp + δ/2
        y2 = f(xs...)
        x[i] = tmp
        Δ[i] = (y2-y1)/δ
        if eltype(x) <: Complex
            # derivative with respect to imaginary part
            x[i] = tmp - im*δ/2
            y1 = f(xs...)
            x[i] = tmp + im*δ/2
            y2 = f(xs...)
            x[i] = tmp
            Δ[i] += im*(y2-y1)/δ
        end
    end
    return grads
end


@testset ExtendedTestSet "circuit gradients" begin

    # construct parametrized circuit
    N = 4
    rz = RzGate(1.5π)
    ps = PhaseShiftGate(0.3)
    ry = RyGate(√2)
    n = randn(Float64, 3)
    n /= norm(n)
    rg = RotationGate(0.2π, n)
    cgc = CircuitGateChain{N}([
        single_qubit_circuit_gate(3, HadamardGate(), N),
        controlled_circuit_gate((1, 4), 2, rz, N),
        two_qubit_circuit_gate(2, 3, SwapGate(), N),
        single_qubit_circuit_gate(3, ps, N),
        single_qubit_circuit_gate(3, rg, N),
        single_qubit_circuit_gate(1, ry, N),
    ])
    # measurement operators
    meas = MeasurementOps{N}([Matrix{Float64}(I, 2^N, 2^N), Hermitian(randn(ComplexF64, 2^N, 2^N))])
    c = Circuit(cgc, meas)

    # input quantum state
    ψ = randn(ComplexF64, 2^N)

    # fictitious gradients of cost function with respect to circuit output
    Δ = [0.3, -1.2]

    grads = Flux.gradient(() -> dot(Δ, apply(c, ψ)), Flux.Params([rz.θ, ps.ϕ, ry.θ, rg.nθ]))

    # arguments used implicitly via references
    f(args...) = dot(Δ, apply(c, ψ))
    @test all(isapprox.(ngradient(f, rz.θ, ps.ϕ, ry.θ, rg.nθ),
        (grads[rz.θ], grads[ps.ϕ], grads[ry.θ], grads[rg.nθ]), rtol=1e-5, atol=1e-5))
end