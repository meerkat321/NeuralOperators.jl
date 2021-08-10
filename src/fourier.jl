using Flux
using FFTW
using Tullio

export
    SpectralConv1d,
    FNO

struct SpectralConv1d{T,S}
    weight::T
    in_channel::S
    out_channel::S
    modes::S
    σ::Function
end

function SpectralConv1d(
    ch::Pair{<:Integer,<:Integer},
    modes::Integer,
    σ::Function=identity;
    init=Flux.glorot_uniform,
    T::DataType=Float32
)
    in_chs, out_chs = ch
    scale = one(T) / (in_chs * out_chs)
    weights = scale * init(out_chs, in_chs, modes)

    return SpectralConv1d(weights, in_chs, out_chs, modes, σ)
end

Flux.@functor SpectralConv1d

function (m::SpectralConv1d)(𝐱::AbstractArray)
    𝐱_fft = rfft(𝐱, 1) # [x, in_chs, batch]
    𝐱_selected = 𝐱_fft[1:m.modes, :, :] # [modes, in_chs, batch]

    # [modes, out_chs, batch] <- [modes, in_chs, batch] [out_chs, in_chs, modes]
    @tullio 𝐱_weighted[m, o, b] := 𝐱_selected[m, i, b] * m.weight[o, i, m]

    d = size(𝐱, 1) ÷ 2 + 1 - m.modes
    𝐱_padded = cat(𝐱_weighted, zeros(Float32, d, size(𝐱)[2:end]...), dims=1)

    𝐱_out = irfft(𝐱_padded , size(𝐱, 1), 1)

    return m.σ.(𝐱_out)
end

function FourierBlock(
    ch::Pair{<:Integer,<:Integer},
    modes::Integer,
    σ::Function=identity
)
    return Chain(
        Parallel(+,
            Conv((1, ), ch),
            SpectralConv1d(ch, modes)
        ),
        x -> σ.(x)
    )
end

function FNO()
    modes = 16
    ch = 64 => 64

    return Chain(
        Conv((1, ), 2=>64),
        FourierBlock(ch, modes, relu),
        FourierBlock(ch, modes, relu),
        FourierBlock(ch, modes, relu),
        FourierBlock(ch, modes),
        Conv((1, ), 64=>128, relu),
        Conv((1, ), 128=>1),
        flatten
    )
end

# loss(m::SpectralConv1d, x, x̂) = sum(abs2, x̂ .- m(x)) / len
