# Included from runtests.jl.

using Random: MersenneTwister

@testset "entropy vectors of distributions" begin
    # uniform over all outcomes: every subset of k binary variables has k bits
    for n in 1:4
        h = Xitip.entropy_vector(ones(2^n), n, 2)
        @test all(h[S] ≈ count_ones(S) for S in 1:(1 << n) - 1)
    end
    # a deterministic variable has no entropy at all
    p = zeros(4); p[1] = 1
    @test Xitip.entropy_vector(p, 2, 2) ≈ [0, 0, 0]
    # X, Y independent fair bits and Z = X xor Y: every pair determines the third
    p = zeros(8)
    for x in 0:1, y in 0:1
        p[1 + x + 2y + 4((x + y) % 2)] = 0.25
    end
    h = Xitip.entropy_vector(p, 3, 2)
    @test h ≈ [1, 1, 2, 1, 2, 2, 2]              # H(X), H(Y), H(X,Y), H(Z), ...
    @test evaluate("I(X;Y)", ["X", "Y", "Z"], h) ≈ 0
    @test evaluate("I(X;Y|Z)", ["X", "Y", "Z"], h) ≈ 1
end

@testset "sampling the cone" begin
    rng = MersenneTwister(11)
    for n in 2:4
        cloud = entropic_samples(n; count=60, rng=rng)
        @test size(cloud) == ((1 << n) - 1, 60)
        # every sample comes from a distribution, so the cone must hold it
        for j in axes(cloud, 2), g in Xitip.elemental_inequalities(n)
            @test sum(Float64(v) * cloud[k, j] for (k, v) in g.a) > -1e-9
        end
        # normalised: the joint entropy of every sample is 1
        @test all(≈(1), cloud[end, :])
    end
    # without normalising, the joint entropy is at most log2 of the alphabet^n
    cloud = entropic_samples(3; count=20, alphabet=3, normalize=false, rng=rng)
    @test all(cloud[end, :] .<= 3 * log2(3) + 1e-9)
    @test_throws XitipError entropic_samples(0)
    @test_throws XitipError entropic_samples(2; style=:uniform)
end

@testset "structured sampling reaches across the cone" begin
    # a joint distribution drawn outright is nearly always close to
    # independent, so it sits against the I(X;Y) = 0 facet and leaves the
    # rest of the cone empty; the structured sampler is what fills it
    names = ["X", "Y"]
    spread(style) = begin
        cloud = entropic_samples(2; count=400, alphabet=3, style=style,
                                 rng=MersenneTwister(5))
        dependent = count(j -> evaluate("I(X;Y)", names, cloud[:, j]) > 0.5,
                          axes(cloud, 2))
        lopsided = count(j -> cloud[1, j] < 0.5 || cloud[2, j] < 0.5,
                         axes(cloud, 2))
        (dependent, lopsided) ./ Base.size(cloud, 2)
    end
    structured, random = spread(:structured), spread(:random)
    @test structured[1] > 2 * random[1]          # strongly dependent samples
    @test structured[2] > 2 * random[2]          # samples near a lone ray
    @test random[1] < 0.1                        # the pile-up being fixed
end

@testset "evaluating expressions at a point" begin
    names = ["X", "Y"]
    @test evaluate("H(X)", names, [1.0, 2.0, 2.5]) == 1
    @test evaluate("H(X,Y)", names, [1.0, 2.0, 2.5]) == 2.5
    @test evaluate("H(X|Y)", names, [1.0, 2.0, 2.5]) == 0.5
    @test evaluate("I(X;Y)", names, [1.0, 2.0, 2.5]) == 0.5
    @test evaluate("2 H(X) + 1", names, [1.0, 2.0, 2.5]) == 3
    # the short form takes the default names
    @test evaluate("I(X;Y)", [1.0, 1.0, 2.0]) == 0

    @test Xitip.expression_coefficients("I(X;Y)", names) ==
          Dict(1 => 1, 2 => 1, 3 => -1)
    @test_throws XitipError Xitip.expression_coefficients("I(X;W)", names)
    # a statement that is not an expression cannot be read as one
    @test_throws SyntaxError Xitip.expression_coefficients("X/Y/Z", ["X","Y","Z"])
    @test_throws SyntaxError Xitip.expression_coefficients("I(X;;Y)", names)
end

@testset "the cone for one and two variables" begin
    @test cone_rays(1) == [[1] => "X"]
    rays = cone_rays(2)
    @test length(rays) == 3
    # each ray is in the cone and sits on two of its three facets
    for (ray, _) in rays
        tight = 0
        for g in Xitip.elemental_inequalities(2)
            value = sum(Float64(v) * ray[k] for (k, v) in g.a)
            @test value > -1e-12
            abs(value) < 1e-12 && (tight += 1)
        end
        @test tight == 2
    end
    # and the rays are what the meanings say they are
    @test evaluate("H(Y)", ["X", "Y"], Float64.(rays[1].first)) == 0   # Y constant
    @test evaluate("H(X)", ["X", "Y"], Float64.(rays[2].first)) == 0   # X constant
    @test evaluate("H(X|Y)", ["X", "Y"], Float64.(rays[3].first)) == 0 # X = Y
    @test_throws XitipError cone_rays(3)
end

@testset "projection" begin
    rng = MersenneTwister(12)
    cloud = entropic_samples(3; count=120, rng=rng)
    coordinates, share = Xitip.project(cloud, 2)
    @test size(coordinates) == (2, 120)
    @test all(0 .<= share .<= 1) && sum(share) <= 1 + 1e-9
    @test share[1] >= share[2]                      # strongest direction first
    # a cloud that really lies on one line keeps all of its spread in one
    line = [1.0, 2.0, 2.5] * collect(range(-1, 1; length=50))'
    _, one_share = Xitip.project(line, 2)
    @test one_share[1] > 0.999
end

@testset "geometry plots need the extension" begin
    for call in (() -> plot_entropy_cone(),
                 () -> plot_entropy_space(3))
        err = try call() catch e; e end
        @test err isa XitipError
        @test occursin("CairoMakie", sprint(showerror, err))
    end
end
