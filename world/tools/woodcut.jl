# Woodcut filter (s133, after Dürer's Small Passion woodcuts): a picture of the island as black lines on paper.
# Strokes follow the light's contours (structure tensor of luminance, line integral convolution of grain noise);
# darker tone ranks get one stroke layer, then a cross layer at 60°, then solid ink; strong colour edges outline.
# Usage: include("tools/woodcut.jl"); woodcut_file("site/img/beach-hut.png", "media/x.png")
using FileIO, Colors, Random

function wc_boxblur(a, r)
    H, W = size(a); t = similar(a); o = similar(a)
    for j in 1:W, i in 1:H
        s = zero(eltype(a)); n = 0
        for k in max(1, i - r):min(H, i + r); s += a[k, j]; n += 1; end
        t[i, j] = s / n
    end
    for j in 1:W, i in 1:H
        s = zero(eltype(a)); n = 0
        for k in max(1, j - r):min(W, j + r); s += t[i, k]; n += 1; end
        o[i, j] = s / n
    end
    o
end
wc_blur(a, r, passes = 2) = foldl((x, _) -> wc_boxblur(x, r), 1:passes; init = a)

function wc_sobel(a)
    H, W = size(a); gx = zeros(Float32, H, W); gy = zeros(Float32, H, W)
    for j in 2:W-1, i in 2:H-1
        gx[i, j] = (a[i-1, j+1] + 2a[i, j+1] + a[i+1, j+1]) - (a[i-1, j-1] + 2a[i, j-1] + a[i+1, j-1])
        gy[i, j] = (a[i+1, j-1] + 2a[i+1, j] + a[i+1, j+1]) - (a[i-1, j-1] + 2a[i-1, j] + a[i-1, j+1])
    end
    gx, gy
end

function wc_lic(noise, dx, dy, len)
    H, W = size(noise); out = zeros(Float32, H, W)
    Threads.@threads for j in 1:W
        for i in 1:H
            s = noise[i, j]; n = 1
            for sgn in (1f0, -1f0)
                x = Float32(j); y = Float32(i); px = dx[i, j] * sgn; py = dy[i, j] * sgn
                for _ in 1:len
                    ii = clamp(round(Int, y), 1, H); jj = clamp(round(Int, x), 1, W)
                    vx = dx[ii, jj]; vy = dy[ii, jj]
                    if vx * px + vy * py < 0; vx = -vx; vy = -vy; end   # axial field: keep heading
                    x += vx; y += vy; px = vx; py = vy
                    (1 <= x <= W && 1 <= y <= H) || break
                    s += noise[round(Int, y), round(Int, x)]; n += 1
                end
            end
            out[i, j] = s / n
        end
    end
    out
end

function wc_ranknorm(a)
    p = sortperm(vec(a)); r = similar(vec(a)); r[p] .= range(0f0, 1f0; length = length(a)); reshape(r, size(a))
end

function wc_grain(H, W, cell)
    g = rand(Float32, cld(H, cell) + 1, cld(W, cell) + 1)
    [g[cld(i, cell), cld(j, cell)] for i in 1:H, j in 1:W]
end

"""
    woodcut(src; edge = 0.62, solid = 0.93, k1 = 0.35, k2 = 0.65, seed = 1509) -> Matrix{RGB{Float32}}

`k1`/`k2`: darkness ranks where the first / cross stroke layers begin; `solid`: rank above which it is all ink;
`edge`: colour gradient that draws an outline. Flat areas (sky) hatch at -30° only if dark enough, so a light sky stays paper.
"""
function woodcut(src; edge = 0.62f0, solid = 0.93f0, k1 = 0.35f0, k2 = 0.65f0, seed = 1509, smooth = 14, len1 = 18, len2 = 12,
                 cell = 2, fallback_deg = -30f0, flat = 0.15f0,
                 paper = RGB{Float32}(0.93, 0.90, 0.83), inkc = RGB{Float32}(0.08, 0.07, 0.06))
    H, W = size(src)
    lum = Float32[Float32(Gray(c)) for c in src]
    gx, gy = wc_sobel(wc_blur(lum, 2))
    Jxx = wc_blur(gx .* gx, smooth); Jxy = wc_blur(gx .* gy, smooth); Jyy = wc_blur(gy .* gy, smooth)
    θ = @. 0.5f0 * atan(2Jxy, Jxx - Jyy)
    coh = @. sqrt((Jxx - Jyy)^2 + 4Jxy^2) / (Jxx + Jyy + 1f-4)
    w = clamp.((coh .- flat) ./ 0.35f0, 0f0, 1f0)
    fb = 2 * (deg2rad(Float32(fallback_deg)) - Float32(pi) / 2)
    θb = @. 0.5f0 * atan(w * sin(2θ) + (1 - w) * sin(fb), w * cos(2θ) + (1 - w) * cos(fb))
    Random.seed!(seed)
    r1 = wc_ranknorm(wc_lic(wc_grain(H, W, cell), cos.(θb .+ Float32(pi) / 2), sin.(θb .+ Float32(pi) / 2), len1))
    r2 = wc_ranknorm(wc_lic(wc_grain(H, W, cell), cos.(θb .+ Float32(pi) / 2 .+ 1.05f0), sin.(θb .+ Float32(pi) / 2 .+ 1.05f0), len2))
    emag = zeros(Float32, H, W)
    for k in 1:3
        ex, ey = wc_sobel(wc_blur(Float32[(red(c), green(c), blue(c))[k] for c in src], 2, 2))
        emag .+= ex .^ 2 .+ ey .^ 2
    end
    emag .= sqrt.(emag)
    rl = wc_ranknorm(wc_blur(lum, 1, 1))
    map(CartesianIndices(lum)) do I
        tt = 1f0 - rl[I]
        c1 = clamp((tt - k1) / (1 - k1) * 0.9f0, 0f0, 0.5f0)
        c2 = clamp((tt - k2) / (1 - k2) * 0.9f0, 0f0, 0.45f0)
        (r1[I] < c1) | (r2[I] < c2) | (tt > solid) | (emag[I] > edge) ? inkc : paper
    end
end

woodcut_file(inpath, outpath; kw...) = (save(outpath, woodcut(load(inpath); kw...)); outpath)

"""
    woodcut_island(src; period = 7, wmin = 0.6, wmax = 3.6, shadow = 0.12, edge = 0.55, minspeck = 220) -> (img, sea fraction)

The print version (s133, after the critic: a woodcut is masses, not scratches): the sea (blue over green and red) is cut
as parallel horizontal lines that thicken where the water is darker, with a slow swell; the land stays white paper with a
bold shoreline and colour outlines; only the darkest `shadow` share of the land goes solid black; ink specks on the land
smaller than `minspeck` px (flower and pebble rings) are dropped. Made for site/img/island-traced.png (posted s133).
"""
function woodcut_island(src; period = 7f0, wmin = 0.6f0, wmax = 3.6f0, shadow = 0.12f0, edge = 0.55f0, minspeck = 220)
    H, W = size(src)
    R = Float32[red(c) for c in src]; G = Float32[green(c) for c in src]; B = Float32[blue(c) for c in src]
    Rb = wc_blur(R, 2); Gb = wc_blur(G, 2); Bb = wc_blur(B, 2)
    sea = @. (Bb > Gb + 0.04f0) & (Bb > Rb + 0.12f0)
    sea = wc_blur(Float32.(sea), 3) .> 0.5f0
    lum = @. 0.3f0 * Rb + 0.59f0 * Gb + 0.11f0 * Bb
    landvals = sort(lum[.!sea]); thr = landvals[max(1, round(Int, shadow * length(landvals)))]
    ink = falses(H, W)
    for j in 1:W, i in 1:H
        if sea[i, j]
            d = clamp((0.75f0 - lum[i, j]) / 0.6f0, 0f0, 1f0)
            y = i + 1.6f0 * sin(j / 37f0) + 0.8f0 * sin(j / 11f0 + i / 50f0)
            ph = mod(y, period); ph = min(ph, period - ph)
            ink[i, j] = ph < (wmin + (wmax - wmin) * d) / 2
        else
            ink[i, j] = lum[i, j] < thr
        end
    end
    emag = zeros(Float32, H, W)
    for C in (R, G, B)
        ex, ey = wc_sobel(wc_blur(C, 3, 2)); emag .+= ex .^ 2 .+ ey .^ 2
    end
    emag .= sqrt.(emag)
    sx, sy = wc_sobel(Float32.(sea))
    shore = sqrt.(sx .^ 2 .+ sy .^ 2) .> 0.5f0
    ink .|= (emag .> edge) .& .!sea
    ink .|= wc_blur(Float32.(shore), 1, 1) .> 0.2f0
    lab = zeros(Int, H, W); sizes = Int[]; stack = Tuple{Int,Int}[]
    for j in 1:W, i in 1:H
        (ink[i, j] && !sea[i, j] && lab[i, j] == 0) || continue
        push!(sizes, 0); id = length(sizes); push!(stack, (i, j)); lab[i, j] = id
        while !isempty(stack)
            a, b = pop!(stack); sizes[id] += 1
            for (da, db) in ((1, 0), (-1, 0), (0, 1), (0, -1))
                x, y = a + da, b + db
                (1 <= x <= H && 1 <= y <= W && ink[x, y] && !sea[x, y] && lab[x, y] == 0) || continue
                lab[x, y] = id; push!(stack, (x, y))
            end
        end
    end
    for j in 1:W, i in 1:H
        lab[i, j] > 0 && sizes[lab[i, j]] < minspeck && (ink[i, j] = false)
    end
    paper = RGB{Float32}(0.93, 0.90, 0.83); inkc = RGB{Float32}(0.08, 0.07, 0.06)
    map(x -> x ? inkc : paper, ink), count(sea) / length(sea)
end
