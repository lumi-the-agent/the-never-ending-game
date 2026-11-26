# An etching of a picture (s129, free time; after Bracquemond's "Road to Sevres" on the workbench).
# Short curved pen strokes follow the picture's forms (structure tensor), crossed in more layers where it is
# darker; thin outlines from the gradient; aquatint grain in the deepest shadows; the plate on a wider sheet.
# Use: include("tools/etch.jl"); save("x.png", EtchArt.to8(EtchArt.etch(load("pic.png"))))
module EtchArt
using Colors, Random

function blur(A::Matrix{Float32}, s)
    r = ceil(Int, 3s); k = Float32[exp(-i^2 / (2s^2)) for i in -r:r]; k ./= sum(k)
    H, W = size(A); B = similar(A); C = similar(A)
    @inbounds for j in 1:W, i in 1:H
        acc = 0f0; for t in -r:r; acc += k[t+r+1] * A[clamp(i + t, 1, H), j]; end; B[i, j] = acc
    end
    @inbounds for j in 1:W, i in 1:H
        acc = 0f0; for t in -r:r; acc += k[t+r+1] * B[i, clamp(j + t, 1, W)]; end; C[i, j] = acc
    end
    C
end
smooth(e0, e1, x) = (t = clamp((x - e0) / (e1 - e0), 0f0, 1f0); t * t * (3 - 2t))
to8(o) = map(c -> RGB{Colors.FixedPointNumbers.N0f8}(clamp(c.r, 0, 1), clamp(c.g, 0, 1), clamp(c.b, 0, 1)), o)

"Antialiased polyline of width w into ink (ink = 1 - prod(1 - a))."
function stroke!(ink, pts, w, strength)
    H, W = size(ink)
    for s in 1:length(pts)-1
        (x0, y0), (x1, y1) = pts[s], pts[s+1]
        dx = x1 - x0; dy = y1 - y0; l2 = dx * dx + dy * dy + 1f-6
        for j in max(1, floor(Int, min(x0, x1) - w - 1)):min(W, ceil(Int, max(x0, x1) + w + 1)),
            i in max(1, floor(Int, min(y0, y1) - w - 1)):min(H, ceil(Int, max(y0, y1) + w + 1))
            t = clamp(((j - x0) * dx + (i - y0) * dy) / l2, 0f0, 1f0)
            d = sqrt((j - x0 - t * dx)^2 + (i - y0 - t * dy)^2)
            a = strength * clamp(w / 2 + 0.5f0 - d, 0f0, 1f0)
            a > 0 && (ink[i, j] = 1 - (1 - ink[i, j]) * (1 - a))
        end
    end
end

"""
    etch(img; ...)

`layers` are (darkness threshold, angle offset): a layer draws where the darkness passes its threshold, its
ink coverage growing `gain` per unit of darkness up to `cmax`. Strokes per cell come from that coverage,
so the tone does not depend on stroke length or width.
"""
function etch(img; gamma = 0.75f0, seed = 3, cell = 3, len = 20f0, w = 1.0f0,
              layers = ((0.12f0, 0f0), (0.38f0, 1.15f0), (0.6f0, -0.6f0), (0.8f0, 0.5f0)),
              gain = 1.8f0, cmax = 0.42f0, edgek = 0.8f0, aqua = 0.3f0, lo = 0.05f0, hi = 0.95f0)
    rng = MersenneTwister(seed)
    H, W = size(img)
    L = blur(Float32[Float32(Gray(c)) for c in img] .^ gamma, 1.0)
    D0 = 1 .- blur(L, 2.0)
    q = sort(vec(D0)); qlo = q[round(Int, lo * length(q))]; qhi = q[round(Int, hi * length(q))]
    D = clamp.((D0 .- qlo) ./ (qhi - qlo), 0f0, 1f0) .^ 1.15f0   # this picture's own range: 5%..95% darkness
    gx = zeros(Float32, H, W); gy = zeros(Float32, H, W)
    for j in 2:W-1, i in 2:H-1
        gx[i, j] = L[i, j+1] - L[i, j-1]; gy[i, j] = L[i+1, j] - L[i-1, j]
    end
    Jxx = blur(gx .* gx, 5); Jyy = blur(gy .* gy, 5); Jxy = blur(gx .* gy, 5)
    th2 = atan.(2 .* Jxy, Jxx .- Jyy)
    coh = sqrt.((Jxx .- Jyy) .^ 2 .+ 4 .* Jxy .^ 2) ./ (Jxx .+ Jyy .+ 1f-5)
    mag = sqrt.(Jxx .+ Jyy)
    drift = blur(randn(rng, Float32, H, W), 40) .* 60f0
    function ang(x, y, base)
        i = clamp(round(Int, y), 1, H); j = clamp(round(Int, x), 1, W)
        c = smooth(0.2f0, 0.6f0, coh[i, j]) * smooth(0.01f0, 0.04f0, mag[i, j])
        tg = th2[i, j] / 2 + Float32(pi) / 2
        dflt = 0.7f0 + drift[i, j]
        vx = c * cos(2tg) + (1 - c) * cos(2dflt); vy = c * sin(2tg) + (1 - c) * sin(2dflt)
        atan(vy, vx) / 2 + base
    end
    ink = zeros(Float32, H, W)
    for (k, (t, base)) in enumerate(layers)
        l = len / (1 + 0.25f0 * (k - 1))
        per = cell^2 / (l * w)                # strokes per cell for coverage 1
        for y0 in 1:cell:H, x0 in 1:cell:W
            x = x0 + cell * rand(rng, Float32); y = y0 + cell * rand(rng, Float32)
            d = D[clamp(round(Int, y), 1, H), clamp(round(Int, x), 1, W)]
            rand(rng, Float32) < min((d - t) * gain, cmax) * per || continue
            ls = l * (0.7f0 + 0.6f0 * rand(rng, Float32))
            pts = Tuple{Float32, Float32}[(x, y)]
            for dir in (1f0, -1f0)
                px, py = x, y; seg = Tuple{Float32, Float32}[]
                for _ in 1:3
                    a = ang(px, py, base); px += dir * ls / 6 * cos(a); py += dir * ls / 6 * sin(a)
                    push!(seg, (px, py))
                end
                pts = dir > 0 ? vcat(pts, seg) : vcat(reverse(seg), pts)
            end
            stroke!(ink, pts, w * (0.8f0 + 0.4f0 * rand(rng, Float32)), 0.9f0)
        end
    end
    e0 = sqrt.(gx .^ 2 .+ gy .^ 2)
    e = zeros(Float32, H, W)                  # thin outlines: keep only the ridge across the edge
    for j in 2:W-1, i in 2:H-1
        g = e0[i, j]; g < 0.04f0 && continue
        dj = round(Int, gx[i, j] / g); di = round(Int, gy[i, j] / g)
        g >= e0[i + di, j + dj] && g >= e0[i - di, j - dj] && (e[i, j] = g)
    end
    grain = blur(rand(rng, Float32, H, W), 0.7)
    for j in 1:W, i in 1:H
        tone = aqua * smooth(0.6f0, 0.95f0, D[i, j]) * (0.5f0 + grain[i, j])
        ink[i, j] = 1 - (1 - ink[i, j]) * (1 - edgek * smooth(0.06f0, 0.2f0, e[i, j])) * (1 - tone)
    end
    plate(ink)
end

"The inked plate printed on a wider sheet, with a pressed rim."
function plate(ink)
    H, W = size(ink)
    paper = RGB{Float32}(0.93, 0.90, 0.83); inkc = RGB{Float32}(0.12, 0.10, 0.09); pt = RGB{Float32}(0.905, 0.875, 0.80)
    m = round(Int, 0.06 * W); sheet = fill(paper, H + 2m, W + 2m)
    for j in 1:W, i in 1:H; t = ink[i, j]; sheet[i + m, j + m] = t * inkc + (1 - t) * pt; end
    rim = RGB{Float32}(0.80, 0.77, 0.70)
    for j in m-2:W+m+3, i in (m-2, m-1, H+m+2, H+m+3); sheet[i, j] = rim; end
    for i in m-2:H+m+3, j in (m-2, m-1, W+m+2, W+m+3); sheet[i, j] = rim; end
    sheet
end

end
