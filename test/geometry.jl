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
    @test_throws XitipError entropic_samples(2; style=:grid)
    @test_throws XitipError entropic_samples(3; style=:uniform)
end

@testset "every point of the two-variable cone is entropic" begin
    rng = MersenneTwister(3)
    for _ in 1:200
        a, b = rand(rng), rand(rng)
        a + b < 1 && ((a, b) = (1 - a, 1 - b))    # fold into the triangle
        h = [a, b, 1.0] .* (0.2 + 3 * rand(rng))
        p, alphabet = Xitip.entropic_distribution(h)
        @test sum(p) ≈ 1
        @test Xitip.entropy_vector(p, 2, alphabet) ≈ h
    end
    # the rays and the apex are the corner cases
    for (ray, _) in cone_rays(2)
        p, alphabet = Xitip.entropic_distribution(Float64.(ray))
        @test Xitip.entropy_vector(p, 2, alphabet) ≈ ray
    end
    p, alphabet = Xitip.entropic_distribution([0.0, 0.0, 0.0])
    @test Xitip.entropy_vector(p, 2, alphabet) ≈ [0, 0, 0]

    @test_throws XitipError Xitip.entropic_distribution([1.0, 1.0])
    @test_throws XitipError Xitip.entropic_distribution([1.0, 0.2, 0.5])  # H(X|Y)<0

    # a marginal with a prescribed entropy, including past one bit
    for h in (0.0, 0.3, 1.0, 1.7, 4.5)
        q = Xitip.marginal_with_entropy(h)
        @test sum(q) ≈ 1
        @test -sum(x * log2(x) for x in q if x > 0; init=0.0) ≈ h atol=1e-9
    end

    # uniform sampling covers the triangle evenly: a region gets the share of
    # the samples that its share of the area says it should
    cloud = entropic_samples(2; count=8000, style=:uniform, rng=rng)
    @test all(≈(1), cloud[3, :])
    corner(c) = count(j -> c[1, j] > 0.9 && c[2, j] > 0.9, axes(c, 2)) / Base.size(c, 2)
    edge(c) = count(j -> c[1, j] < 0.15, axes(c, 2)) / Base.size(c, 2)
    @test corner(cloud) ≈ 0.01 / 0.5 rtol=0.3         # area 0.01 of the 0.5
    @test edge(cloud) ≈ 0.01125 / 0.5 rtol=0.3        # area 0.01125
    # and it covers the triangle, which sampling distributions does not:
    # count how many cells of a grid over the triangle hold a sample
    cells(c) = Set((clamp(ceil(Int, c[1, j] * 40), 1, 40),
                    clamp(ceil(Int, c[2, j] * 40), 1, 40)) for j in axes(c, 2))
    inside = Set((i, j) for i in 1:40, j in 1:40 if (i + j - 1) / 40 >= 1)
    filled(c) = length(intersect(cells(c), inside)) / length(inside)
    structured = entropic_samples(2; count=8000, alphabet=3, rng=rng)
    @test filled(cloud) > 0.99
    @test filled(structured) < 0.6
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

@testset "the I-measure" begin
    # Z = X xor Y: each pair is independent, yet the three together are not
    h = entropy_vector([1, 0, 0, 1, 0, 1, 1, 0] ./ 4, 3, 2)
    @test imeasure(h) == ["H(X|Y,Z)" => 0.0, "H(Y|X,Z)" => 0.0,
                          "H(Z|X,Y)" => 0.0, "I(X;Y|Z)" => 1.0,
                          "I(X;Z|Y)" => 1.0, "I(Y;Z|X)" => 1.0,
                          "I(X;Y;Z)" => -1.0]
    # the atoms always sum to the joint entropy, whatever the distribution
    rng = MersenneTwister(21)
    for n in 2:4
        cloud = entropic_samples(n; count=40, alphabet=3, normalize=false,
                                 rng=rng)
        for j in axes(cloud, 2)
            atoms = imeasure(cloud[:, j])
            @test sum(last, atoms) ≈ cloud[end, j]
            # and each atom equals the quantity it is named after
            for (name, value) in atoms
                @test evaluate(name, Xitip.default_names(n), cloud[:, j]) ≈
                      value atol=1e-9
            end
        end
    end
    @test_throws XitipError imeasure([1.0, 1.0, 2.0], ["X", "Y", "Z"])
end

@testset "the three-variable cone is a bipyramid" begin
    # the five vertices, and a distribution sitting on each of them
    joint(f) = begin
        p = zeros(8)
        for x in 0:1, y in 0:1
            X, Y, Z = f(x, y)
            p[1 + X + 2Y + 4Z] += 0.25
        end
        p
    end
    cases = [(x, y) -> (x, x, x),  (x, y) -> (x, x, y),
             (x, y) -> (x, y, x),  (x, y) -> (y, x, x),
             (x, y) -> (x, y, xor(x, y))]
    for (case, (vertex, _)) in zip(cases, shared_cone_vertices())
        b, c = shared_slice(entropy_vector(joint(case), 3, 2))
        @test b ≈ vertex
        @test c ≈ 1 - sum(vertex)          # the slice fixes the total at 1
    end
    # the equator is exactly I(X;Y;Z) = 0, and only the xor apex is below it
    @test [1 - sum(v) for (v, _) in shared_cone_vertices()] ==
          [1.0, 0.0, 0.0, 0.0, -0.5]

    # every sample lands inside the body: b >= 0 and no two of them exceed 1
    rng = MersenneTwister(22)
    cloud = entropic_samples(3; count=400, alphabet=3, normalize=false, rng=rng)
    seen = 0
    for j in axes(cloud, 2)
        slice = shared_slice(cloud[:, j])
        slice === nothing && continue
        seen += 1
        b, c = slice
        @test all(b .>= -1e-9)
        @test all(b[i] + b[k] <= 1 + 1e-9 for i in 1:3 for k in i+1:3)
        @test c ≈ 1 - sum(b) atol=1e-9
    end
    @test seen > 300

    # a noisy xor stays on the apex however much noise there is: the three
    # conditional informations stay equal, and the slice divides the scale out
    for q in (0.0, 0.3, 0.7, 0.95)
        p = zeros(8)
        for x in 0:1, y in 0:1, z in 0:1
            p[1 + x + 2y + 4z] = 0.25 * ((1 - q) * (z == xor(x, y)) + q * 0.5)
        end
        b, c = shared_slice(entropy_vector(p, 3, 2))
        @test b ≈ [0.5, 0.5, 0.5]
        @test c ≈ -0.5
    end
    # three independent variables share nothing, so there is no slice
    @test shared_slice(Float64[1, 1, 2, 1, 2, 2, 3]) === nothing
    @test_throws XitipError shared_slice([1.0, 1.0, 2.0])
end

@testset "the facets are the inequalities" begin
    V = [v for (v, _) in shared_cone_vertices()]
    # each facet's inequality is tight exactly on that facet's three vertices
    for (corners, name) in shared_cone_facets()
        statement = replace(name, " = 0" => " >= 0")
        w, private = shared_coefficients(statement)
        @test all(iszero, private)
        at(b) = w[1] + sum(w[2:4] .* b)
        @test all(isapprox(at(V[k]), 0; atol=1e-9) for k in corners)
        @test all(at(V[k]) > 1e-9 for k in eachindex(V) if !(k in corners))
    end
    # six facets, five vertices, so nine edges: Euler holds for the bipyramid
    edges = Set{Tuple{Int,Int}}()
    for (corners, _) in shared_cone_facets(), i in corners, j in corners
        i < j && push!(edges, (i, j))
    end
    @test length(edges) == 9
    @test length(shared_cone_facets()) - length(edges) + length(V) == 2
end

@testset "a statement is provable when no vertex escapes" begin
    V = [v for (v, _) in shared_cone_vertices()]
    holds(statement) = begin
        w, private = shared_coefficients(statement)
        all(private .>= -1e-9) &&
            all(w[1] + sum(w[2:4] .* b) >= -1e-9 for b in V)
    end
    # the picture and the prover agree, on statements the slice can see
    for statement in ("I(X;Y;Z) >= 0", "I(X;Y) <= I(X;Y|Z)",
                      "I(X;Y|Z) <= I(X;Y)",
                      "H(X,Y,Z) <= H(X,Y) + H(Z)",
                      "I(X;Y|Z) >= 0", "I(X;Y) >= 0",
                      "I(X;Y|Z) + I(X;Z|Y) >= 0",
                      "I(X;Y) + I(X;Z) >= I(X;Y|Z)",
                      "2 I(X;Y|Z) >= I(X;Y)")
        @test holds(statement) == prove(statement)
    end
    # a constant term rides along in the same coordinates
    w, _ = shared_coefficients("I(X;Y;Z) + 1 >= 0")
    @test w[1] ≈ 1 + 1.0
    @test_throws XitipError shared_coefficients("X/Y/Z")
    @test_throws XitipError shared_coefficients("I(X;Y) >= 0", ["X", "Y"])
end

@testset "families of distributions" begin
    # two variables: every family starts at X = Y when the channel is clean
    for (name, curve) in distribution_families(2)
        @test size(curve, 1) == 3
        for j in axes(curve, 2)                     # all inside the cone
            for g in Xitip.elemental_inequalities(2)
                @test sum(Float64(v) * curve[k, j] for (k, v) in g.a) > -1e-9
            end
        end
    end
    named = Dict(distribution_families(2))
    # a symmetric channel keeps H(X) = H(Y), so it runs down the middle
    bsc = named["binary symmetric channel"]
    @test all(bsc[1, j] ≈ bsc[2, j] for j in axes(bsc, 2))
    @test bsc[:, 1] ≈ [1, 1, 1]                     # clean: X = Y
    @test bsc[3, end] ≈ 2                           # useless: independent bits
    # independence and functions lie on the faces that define them
    indep = named["X and Y independent"]
    @test all(isapprox(evaluate("I(X;Y)", indep[:, j]), 0; atol=1e-9)
              for j in axes(indep, 2))
    fn = named["Y a function of X"]
    @test all(isapprox(evaluate("H(Y|X)", fn[:, j]), 0; atol=1e-9)
              for j in axes(fn, 2))
    # the asymmetric channels are asymmetric
    for key in ("erasure channel", "Z channel")
        curve = named[key]
        @test any(!isapprox(curve[1, j], curve[2, j]) for j in axes(curve, 2))
    end

    # three variables: a Markov chain lies exactly on one facet
    named = Dict(distribution_families(3))
    for key in ("Markov chain X -> Y -> Z", "common cause Y -> (X, Z)")
        curve = named[key]
        for j in axes(curve, 2)
            @test isapprox(evaluate("I(X;Z|Y)", curve[:, j]), 0; atol=1e-9)
        end
    end
    # and that facet is the one the picture labels
    @test ([1, 2, 4] => "I(X;Z|Y) = 0") in shared_cone_facets()
    # the noisy parity family never leaves the far apex
    parity = named["Z = X xor Y, noisy"]
    for j in 1:size(parity, 2) - 1                  # the last step is all noise
        b, c = shared_slice(parity[:, j])
        @test b ≈ [0.5, 0.5, 0.5]
        @test c ≈ -0.5
    end

    @test_throws XitipError distribution_families(4)
    @test_throws XitipError distribution_families(2; steps=1)
end

@testset "geometry plots need the extension" begin
    for call in (() -> plot_entropy_cone(),
                 () -> plot_entropy_cone(3),
                 () -> plot_imeasure([1.0, 1.0, 2.0]),
                 () -> plot_entropy_space(3))
        err = try call() catch e; e end
        @test err isa XitipError
        @test occursin("CairoMakie", sprint(showerror, err))
    end
end
