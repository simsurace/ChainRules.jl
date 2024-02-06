@testset "dense LinearAlgebra" begin
    @testset "dot" begin
        @testset "Vector{$T}" for T in (Float64, ComplexF64)
            @gpu test_frule(dot, randn(T, 3), randn(T, 3))
            @gpu test_rrule(dot, randn(T, 3), randn(T, 3))
        end
        @testset "Array{$T, 3}" for T in (Float64, ComplexF64)
            test_frule(dot, randn(T, 3, 4, 5), randn(T, 3, 4, 5))
            test_rrule(dot, randn(T, 3, 4, 5), randn(T, 3, 4, 5))
        end
        @testset "mismatched shapes" begin
           # forward
           @gpu test_frule(dot, randn(3, 5), randn(5, 3))             
           @gpu test_frule(dot, randn(15), randn(5, 3))             
           # reverse
           @gpu test_rrule(dot, randn(3, 5), randn(5, 3))             
           @gpu test_rrule(dot, randn(15), randn(5, 3))             
        end
        @testset "3-arg dot, Array{$T}" for T in (Float64, ComplexF64)
            @gpu_broken test_frule(dot, randn(T, 3), randn(T, 3, 4), randn(T, 4))
            @gpu test_rrule(dot, randn(T, 3), randn(T, 3, 4), randn(T, 4))
        end
        permuteddimsarray(A) = PermutedDimsArray(A, (2,1))
        @testset "3-arg dot, $F{$T}" for T in (Float32, ComplexF32), F in (adjoint, permuteddimsarray)
            A = F(rand(T, 4, 3)) ⊢ F(rand(T, 4, 3))
            test_frule(dot, rand(T, 3), A, rand(T, 4); rtol=1f-3)
            test_rrule(dot, rand(T, 3), A, rand(T, 4); rtol=1f-3)
        end
        @testset "different types" begin
            test_rrule(dot, rand(2), rand(2, 2), rand(ComplexF64, 2))
            test_rrule(dot, rand(2), Diagonal(rand(2)), rand(ComplexF64, 2))

            # Inference failure due to https://github.com/JuliaDiff/ChainRulesCore.jl/issues/407
            test_rrule(dot, Diagonal(rand(2)), rand(2, 2); check_inferred=false)
        end
    end

    @testset "mul!" begin
        test_frule(mul!, rand(4), rand(4, 5), rand(5))
        test_frule(mul!, rand(3, 3), rand(3, 3), rand(3, 3))
        test_frule(mul!, rand(3, 3), rand(), rand(3, 3))

        # Rule with α,β::Bool is only visually more complicated:
        test_frule(mul!, rand(4), rand(4, 5), rand(5), true, true)
        test_frule(mul!, rand(4), rand(4, 5), rand(5), false, true)
        test_frule(mul!, rand(4), rand(4, 5), rand(5), true, false)
        test_frule(mul!, rand(4), rand(4, 5), rand(5), false, false)

        # Rule with nontrivial α, β allocates A*B:
        test_frule(mul!, rand(4), rand(4, 5), rand(5), true, randn())
        test_frule(mul!, rand(4), rand(4, 5), rand(5), randn(), randn())
    end

    @testset "cross" begin
        test_frule(cross, randn(3), randn(3))
        test_frule(cross, randn(ComplexF64, 3), randn(ComplexF64, 3))
        test_rrule(cross, randn(3), randn(3))
        # No complex support for rrule(cross,...

        # mix types
        test_rrule(cross, rand(3), rand(Float32, 3); rtol = 1.0e-7, atol = 1.0e-7)
    end
    @testset "pinv" begin
        @testset "$T" for T in (Float64, ComplexF64)
            test_scalar(pinv, randn(T))
            @test frule((ZeroTangent(), randn(T)), pinv, zero(T))[2] ≈ zero(T)
            @test rrule(pinv, zero(T))[2](randn(T))[2] ≈ zero(T)
        end
        @testset "Vector{$T}" for T in (Float64, ComplexF64)
            test_frule(pinv, randn(T, 3), 0.0)
            test_frule(pinv, randn(T, 3), 0.0)

            # Checking types. TODO do we still need this?
            x = randn(T, 3)
            ẋ = randn(T, 3)
            Δy = copyto!(similar(pinv(x)), randn(T, 3))
            @test frule((ZeroTangent(), ẋ), pinv, x)[2] isa typeof(pinv(x))
            @test rrule(pinv, x)[2](Δy)[2] isa typeof(x)
        end

        @testset "$F{Vector{$T}}" for T in (Float64, ComplexF64), F in (Transpose, Adjoint)
            test_frule(pinv, F(randn(T, 3)))
            test_rrule(pinv, F(randn(T, 3)))

            # Check types.
            # TODO: Do we need this still?
            x, ẋ, x̄ = F(randn(T, 3)), F(randn(T, 3)), F(randn(T, 3))
            y = pinv(x)
            Δy = copyto!(similar(y), randn(T, 3))

            y_fwd, ∂y_fwd = frule((ZeroTangent(),  ẋ), pinv, x)
            @test y_fwd isa typeof(y)
            @test ∂y_fwd isa typeof(y)

            y_rev, back = rrule(pinv, x)
            @test y_rev isa typeof(y)
            @test back(Δy)[2] isa typeof(x)
        end
        @testset "Matrix{$T} with size ($m,$n)" for T in (Float64, ComplexF64),
            m in 1:3,
            n in 1:3

            test_frule(pinv, randn(T, m, n))
            test_rrule(pinv, randn(T, m, n))
        end
    end
    @testset "$f" for f in (det, logdet)
        @testset "$f(::$T)" for T in (Float64, ComplexF64)
            b = (f === logdet && T <: Real) ? abs(randn(T)) : randn(T)
            test_scalar(f, b)
        end
        @testset "$f(::Matrix{$T})" for T in (Float64, ComplexF64)
            B = generate_well_conditioned_matrix(T, 4)
            if f === logdet && float(T) <: Float32
                test_frule(f, B; atol=1e-5, rtol=1e-5)
                test_rrule(f, B; atol=1e-5, rtol=1e-5)
            else
                test_frule(f, B)
                test_rrule(f, B)
            end
        end
        @testset "$f(complex determinant)" begin
            B = randn(ComplexF64, 4, 4)
            U = exp(B - B')
            test_frule(f, U)
            test_rrule(f, U)
        end
        @testset "gpu" begin
            @gpu_broken test_rrule(f, reshape(1:9, 3, 3)+I*pi)
        end
    end
    @testset "logabsdet(::Matrix{$T})" for T in (Float64, ComplexF64)
        B = randn(T, 4, 4)
        test_frule(logabsdet, B)
        test_rrule(logabsdet, B)
        # test for opposite sign of determinant
        test_frule(logabsdet, -B)
        test_rrule(logabsdet, -B)
    end
    @testset "tr" begin
        @gpu test_frule(tr, randn(4, 4))
        @gpu test_rrule(tr, randn(4, 4))
    end
    @testset "sylvester" begin
        @testset "T=$T, m=$m, n=$n" for T in (Float64, ComplexF64), m in (2, 3), n in (1, 3)
            A = randn(T, m, m)
            B = randn(T, n, n)
            C = randn(T, m, n)
            test_frule(sylvester, A, B, C)
            test_rrule(sylvester, A, B, C)
        end
    end
    @testset "lyap" begin
        n = 3
        @testset "Float64" for T in (Float64, ComplexF64)
            A = randn(T, n, n)
            C = randn(T, n, n)
            test_frule(lyap, A, C)
            test_rrule(lyap, A, C)
        end
    end
    VERSION ≥ v"1.9.0" && @testset "kron" begin
        @testset "AbstractVecOrMat{$T1}, AbstractVecOrMat{$T2}" for T1 in (Float64, ComplexF64), T2 in (Float64, ComplexF64)
            @testset "frule" begin
                test_frule(kron, randn(T1, 2), randn(T2, 3))
                test_frule(kron, randn(T1, 2, 3), randn(T2, 5))
                test_frule(kron, randn(T1, 2), randn(T2, 3, 5))
                test_frule(kron, randn(T1, 2, 3), randn(T2, 5, 7))
            end
            @testset "rrule" begin
                test_rrule(kron, randn(T1, 2), randn(T2, 3))

                test_rrule(kron, Diagonal(randn(T1, 2)), randn(T2, 3))
                test_rrule(kron, randn(T1, 2, 3), randn(T2, 5))

                test_rrule(kron, randn(T1, 2), randn(T2, 3, 5))
                test_rrule(kron, randn(T1, 2), Diagonal(randn(T2, 3)))

                test_rrule(kron, randn(T1, 2, 3), randn(T2, 5, 7))
                test_rrule(kron, Diagonal(randn(T1, 2)), Diagonal(randn(T2, 3)))
            end
        end
    end
end
