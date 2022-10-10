using LibSerialPort, CairoMakie, Sixel, Statistics, FileIO, FixedPointNumbers, LinearAlgebra

plots_dir = mktempdir()

function Base.show(io::IO, ::MIME"text/plain", fig::Scene)
    fname = tempname(plots_dir) .* ".png"
    save(fname, fig)
    sixel_encode(io, load(fname))
end


list_ports()

## Setting for the Arduino
portname = "/dev/ttyACM0"
baudrate = 115200
LibSerialPort.open(portname, baudrate) do sp
    @info "Resetting Arduino"
    # Reset the Arduino
    set_flow_control(sp, dtr=SP_DTR_ON)
    sleep(0.1)
    sp_flush(sp, SP_BUF_INPUT)
    set_flow_control(sp, dtr=SP_DTR_OFF)
end

workdir = pwd()

## The test function
"""
Create the test data, N is the number of samples.
"""
function make_data(N)
    x = range(0, 12π, length=N)
    x, sin.(x) .+ sin.(2x) .+ sin.(3x)
end
## Plotting the test function just to be sure
testx, testy = make_data(2048)

lines(
    testx, testy,
    color=:red, # To match the original article
    axis=(
        xticksvisible=false,
        xticklabelsvisible=false,
        yticksvisible=false,
        yticklabelsvisible=false,
    )
)

save("test_signal.png", current_figure())
current_figure()

## Conversion to ApproxFFT data

# ApproxFFT wants integers, and integers are encoded on two bytes on Arduino, so 
# we need to create a function that translates the output of `make_data` to 16-bits 
# integers.
function to_16_bits(data)
    # We might as well use the full range of available data.
    mini, maxi = extrema(data)
    avg = mean(data)
    span = maxi - mini
    new_span = ((2^15 - 1)) - 1 # ApproxFFT does not like negative values.
    round.(Int16, (data .- avg) ./ span .* new_span)
end

testx, testy = make_data(2048)
testinty = to_16_bits(testy)

lines(
    testx, testinty,
    color=:red, # To match the original article
    axis=(
        xticksvisible=false,
        xticklabelsvisible=false,
        yticksvisible=false,
        yticklabelsvisible=false,
    )
)
##

approxfft_dir = joinpath(workdir, "ApproxFFT")


function write_data_16_bits(N)
    d = make_data(N)[2] |> to_16_bits
    open(joinpath(approxfft_dir, "data.h"), write=true) do f
        write(f, "#ifndef H_DATA\n")
        write(f, "#define H_DATA\n")
        write(f, "int data[] = {\n")
        for n ∈ d
            write(f, "$n,\n")
        end
        write(f, "};\n")
        write(f, "#endif H_DATA\n")
    end
end

write_data_16_bits(256);

## Testing ApproxFFT

approxfft_build = joinpath(approxfft_dir, "build")
approxfft_ino = joinpath(approxfft_dir, "ApproxFFT.ino")

approxfft_build_command = `arduino-cli compile -b arduino:avr:uno -p $portname --build-path "$approxfft_build" -u -v "$approxfft_ino"`
run(approxfft_build_command)


approxfft_testsizes = [4, 8, 16, 32, 64, 128, 256]
approxfft_time = []
approxfft_results = []

LibSerialPort.open(portname, baudrate) do sp
    @info "Testing ApproxFFT"
    # Reset the Arduino
    for N in approxfft_testsizes
        set_flow_control(sp, dtr=SP_DTR_ON)
        sleep(0.1)
        sp_flush(sp, SP_BUF_INPUT)
        set_flow_control(sp, dtr=SP_DTR_OFF)
        st = readline(sp)
        while st != "ready"
            @info "Waiting for arduino to be ready"
            st = readline(sp)
            @info "Arduino said" st
            sleep(0.05)
        end
        @info "Sending N" N
        write(sp, N)
        @info "Awaiting confirmation"
        n_read = read(sp, Int16)
        @info "Control" N n_read

        data = zeros(Int16, n_read)
        read!(sp, data)
        @info "Read data." data
        scale = read(sp, Int8)
        @info "Read scale." scale
        time = float(read(sp, UInt32))
        @info "Read time" time
        push!(approxfft_time, time)
        push!(approxfft_results, data .* 2.0^scale)
        @info "SerialPort status" bytesavailable(sp)
    end

end


#
## Create ExactFFT datasets

exactfft_dir = joinpath(workdir, "ExactFFT")

function write_data_float(N)
    d = make_data(N)[2]
    open(joinpath(exactfft_dir, "data.h"), write=true) do f
        write(f, "#ifndef H_DATA\n")
        write(f, "#define H_DATA\n")
        write(f, "float data[] = {\n")
        for n ∈ d
            write(f, "$n,\n")
        end
        write(f, "};\n")
        write(f, "#endif H_DATA\n")
    end
end

write_data_float(256);


## Uploading the code to the Arduino

exactfft_build = joinpath(exactfft_dir, "build")
exactfft_ino = joinpath(exactfft_dir, "ExactFFT.ino")

exactfft_build_command = `arduino-cli compile -b arduino:avr:uno -p $portname --build-path "$exactfft_build" -u -v "$exactfft_ino"`
run(exactfft_build_command)



exactfft_testsizes = [4, 8, 16, 32, 64, 128, 256]
exactfft_results = []
exactfft_time = []

LibSerialPort.open(portname, baudrate) do sp
    @info "Testing ExactFFT"
    # Reset the Arduino
    for N in exactfft_testsizes
        set_flow_control(sp, dtr=SP_DTR_ON)
        sleep(0.1)
        sp_flush(sp, SP_BUF_INPUT)
        set_flow_control(sp, dtr=SP_DTR_OFF)
        st = readline(sp)
        while st != "ready"
            @info "Waiting for arduino to be ready"
            st = readline(sp)
            @info "Arduino said" st
            sleep(0.05)
        end
        @info "Sending N" N
        write(sp, N)
        @info "Awaiting confirmation"
        n_read = read(sp, Int16)
        @info "Control" N n_read

        data = zeros(Float32, n_read)
        read!(sp, data)
        @info "Read data." data
        time = float(read(sp, UInt32))
        @info "Read time" time
        push!(exactfft_time, time)
        push!(exactfft_results, data)
        @info "SerialPort status" bytesavailable(sp)
    end

end

## Create FloatFFT datasets

floatfft_dir = joinpath(workdir, "FloatFFT")

function write_data_float(N)
    d = make_data(N)[2]
    open(joinpath(floatfft_dir, "data.h"), write=true) do f
        write(f, "#ifndef H_DATA\n")
        write(f, "#define H_DATA\n")
        write(f, "float data[] = {\n")
        for n ∈ d
            write(f, "$n,\n")
        end
        write(f, "};\n")
        write(f, "#endif H_DATA\n")
    end
end

write_data_float(256);


## sines precomputation

step_angles = (-2π ./ (2 .^ (0:9))) .|> Float32
sines = sin.(step_angles)

## Uploading the code to the Arduino

floatfft_build = joinpath(floatfft_dir, "build")
floatfft_ino = joinpath(floatfft_dir, "FloatFFT.ino")

floatfft_build_command = `arduino-cli compile -b arduino:avr:uno -p $portname --build-path "$floatfft_build" -u -v "$floatfft_ino"`
run(floatfft_build_command)



floatfft_testsizes = [4, 8, 16, 32, 64, 128, 256]
floatfft_results = []
floatfft_time = []

LibSerialPort.open(portname, baudrate) do sp
    @info "Testing FloatFFT"
    # Reset the Arduino
    for N in floatfft_testsizes
        set_flow_control(sp, dtr=SP_DTR_ON)
        sleep(0.1)
        sp_flush(sp, SP_BUF_INPUT)
        set_flow_control(sp, dtr=SP_DTR_OFF)
        st = readline(sp)
        while st != "ready"
            @info "Waiting for arduino to be ready"
            st = readline(sp)
            @info "Arduino said" st
            sleep(0.05)
        end
        @info "Sending N" N
        write(sp, N)
        @info "Awaiting confirmation"
        n_read = read(sp, Int16)
        @info "Control" N n_read

        # s = readline(sp)
        # @info "Debug said" s

        data = zeros(Float32, n_read)
        read!(sp, data)
        @info "Read data." data
        time = float(read(sp, UInt32))
        @info "Read time" time
        push!(floatfft_time, time)
        push!(floatfft_results, data)
        @info "SerialPort status" bytesavailable(sp)
    end

end

## Create FixedFFT (16 bits) datasets

fixed16fft_dir = joinpath(workdir, "FixedFFT")

function write_data_fixed_16(N)
    raw_data = make_data(N)[2]
    raw_data = clamp.(raw_data ./ maximum(raw_data), Q0f15)
    d = reinterpret.(UInt16, reinterpret.(Int16, Q0f15.(raw_data)))
    open(joinpath(fixed16fft_dir, "data.h"), write=true) do f
        write(f, "#ifndef H_DATA\n")
        write(f, "#define H_DATA\n\n")
        write(f, "int16_t data[] = {\n")
        for n ∈ d
            write(f, "  $(repr(n)),\n")
        end
        write(f, "};\n\n")
        write(f, "#endif H_DATA\n")
    end
end

write_data_fixed_16(256);

## Precompute sines

step_angles = (-2π ./ (2 .^ (1:9))) .|> Float32
sines = reinterpret.(UInt16, reinterpret.(Int16, Q0f15.(sin.(step_angles))))
step_angles = (-2π ./ (2 .^ (2:9))) .|> Float32
two_sines_sq = reinterpret.(UInt16, reinterpret.(Int16, Q0f15.(clamp.(2 .* sin.(step_angles).^2, Q0f15))))

## FixedFFT 16 bits

fixed16fft_build = joinpath(fixed16fft_dir, "build")
fixed16fft_ino = joinpath(fixed16fft_dir, "FixedFFT.ino")

fixed16fft_build_command = `arduino-cli compile -b arduino:avr:uno -p $portname --build-path "$fixed16fft_build" -u -v "$fixed16fft_ino"`
run(fixed16fft_build_command)



fixed16fft_testsizes = [4, 8, 16, 32, 64, 128, 256]
fixed16fft_results = []
fixed16fft_time = []

LibSerialPort.open(portname, baudrate) do sp
    @info "Testing FixedFFT 16 bits"
    # Reset the Arduino
    for N in fixed16fft_testsizes
        set_flow_control(sp, dtr=SP_DTR_ON)
        sleep(0.1)
        sp_flush(sp, SP_BUF_INPUT)
        set_flow_control(sp, dtr=SP_DTR_OFF)
        st = readline(sp)
        while st != "ready"
            @info "Waiting for arduino to be ready"
            st = readline(sp)
            @info "Arduino said" st
            sleep(0.05)
        end
        @info "Sending N" N
        write(sp, N)
        @info "Awaiting confirmation"
        n_read = read(sp, Int16)
        @info "Control" N n_read

        # s = readline(sp)
        # while s != "done"
        # @info "Debug said" s
        # s = readline(sp)
        # end

        data = zeros(Q0f15, n_read)
        read!(sp, data)
        @info "Read data." data
        time = float(read(sp, UInt32))
        @info "Read time" time
        push!(fixed16fft_time, time)
        # data = repeat(abs.(float.(data[1:2:end]) .+ im .* float.(data[2:2:end])), 2)
        push!(fixed16fft_results, data)
        @info "SerialPort status" bytesavailable(sp)
    end

end


## Create FixedFFT (8 bits) datasets

fixed8fft_dir = joinpath(workdir, "Fixed8FFT")

function write_data_fixed_8(N)
    raw_data = make_data(N)[2]
    raw_data = clamp.(raw_data ./ maximum(raw_data), Q0f7)
    d = reinterpret.(UInt8, reinterpret.(Int8, Q0f7.(raw_data)))
    open(joinpath(fixed8fft_dir, "data.h"), write=true) do f
        write(f, "#ifndef H_DATA\n")
        write(f, "#define H_DATA\n\n")
        write(f, "int8_t data[] = {\n")
        for n ∈ d
            write(f, "  $(repr(n)),\n")
        end
        write(f, "};\n\n")
        write(f, "#endif H_DATA\n")
    end
end

write_data_fixed_8(256);

## FixedCosine 8 bits

fixedcosine8_dir = joinpath(workdir, "FixedCosine")
fixedcosine8_build = joinpath(fixedcosine8_dir, "build")
fixedcosine8_ino = joinpath(fixedcosine8_dir, "FixedCosine.ino")

fixedcosine8_build_command = `arduino-cli compile -b arduino:avr:uno -p $portname --build-path "$fixedcosine8_build" -u -v "$fixedcosine8_ino"`
run(fixedcosine8_build_command)



LibSerialPort.open(portname, baudrate) do sp
    @info "Testing FixedCosine 8 bits"
    # Reset the Arduino
    set_flow_control(sp, dtr=SP_DTR_ON)
    sleep(0.1)
    sp_flush(sp, SP_BUF_INPUT)
    set_flow_control(sp, dtr=SP_DTR_OFF)
    data_c = zeros(Q0f7, 127)
    read!(sp, data_c)
    data_s = zeros(Q0f7, 127)
    read!(sp, data_s)
    lines(data_c)
    lines!(data_s)
end

current_figure()

## FixedFFT 8 bits

fixed8fft_build = joinpath(fixed8fft_dir, "build")
fixed8fft_ino = joinpath(fixed8fft_dir, "FixedFFT.ino")

fixed8fft_build_command = `arduino-cli compile -b arduino:avr:uno -p $portname --build-path "$fixed8fft_build" -u -v "$fixed8fft_ino"`
run(fixed8fft_build_command)



fixed8fft_testsizes = [4, 8, 16, 32, 64, 128, 256]
fixed8fft_results = []
fixed8fft_time = []

LibSerialPort.open(portname, baudrate) do sp
    @info "Testing FixedFFT 8 bits"
    # Reset the Arduino
    for N in fixed8fft_testsizes
        set_flow_control(sp, dtr=SP_DTR_ON)
        sleep(0.1)
        sp_flush(sp, SP_BUF_INPUT)
        set_flow_control(sp, dtr=SP_DTR_OFF)
        st = readline(sp)
        while st != "ready"
            @info "Waiting for arduino to be ready"
            st = readline(sp)
            @info "Arduino said" st
            sleep(0.05)
        end
        @info "Sending N" N
        write(sp, N)
        @info "Awaiting confirmation"
        n_read = read(sp, Int16)
        @info "Control" N n_read

        # s = readline(sp)
        # while s != "done"
        # @info "Debug said" s
        # s = readline(sp)
        # end

        data = zeros(Q0f7, n_read)
        read!(sp, data)
        @info "Read data." data
        time = float(read(sp, UInt32))
        @info "Read time" time
        push!(fixed8fft_time, time)
        # data = repeat(abs.(float.(data[1:2:end]) .+ im .* float.(data[2:2:end])), 2)
        push!(fixed8fft_results, data)
        @info "SerialPort status" bytesavailable(sp)
    end

end


## Checking correctness of my FFTs

using FFTW

data = make_data(256)[2] .|> Float32
true_fft = map(l -> fft(data[1:l]), floatfft_testsizes)

t = Theme(
    Axis=(
        ylabel="Modulus",
        #width=800,
        #height=200,
    )
)
set_theme!(t)

colors = Makie.wong_colors()
f = Figure(resolution=(1200, 800))
expe_float = nothing
expe_exact = nothing
expe_fixed16 = nothing
expe_fixed8 = nothing
res = nothing
dev = Dict([
    "ExactFFT" => Float64[]
    "FloatFFT" => Float64[]
    "Fixed16FFT" => Float64[]
    "Fixed8FFT" => Float64[]
])
for (i, size) ∈ enumerate(floatfft_testsizes)
    mod_fft = abs.(true_fft[i][1:end÷2])
    float_fft = floatfft_results[i][1:end÷2]
    exact_fft = exactfft_results[i][1:end÷2]
    fixed16_fft = fixed16fft_results[i][1:end÷2]
    fixed8_fft = fixed8fft_results[i][1:end÷2]
    push!(dev["FloatFFT"], sqrt(sum(abs2.(mod_fft .- float_fft)) / (size - 1)))
    push!(dev["ExactFFT"], sqrt(sum(abs2.(mod_fft .- exact_fft)) / (size - 1)))
    push!(dev["Fixed16FFT"], sqrt(sum(abs2.(mod_fft .- fixed16_fft)) / (size - 1)))
    push!(dev["Fixed8FFT"], sqrt(sum(abs2.(mod_fft .- fixed8_fft)) / (size - 1)))
    ax = Axis(f[(i+1)÷2, (i+1)%2+1],
        title="Sample size : $size",
        # subtitle="dev(float)=$(round(dev_float, sigdigits=3)), dev(exact)=$(round(dev_exact, sigdigits=3))", 
        yticklabelsvisible=false,
        # limits=(nothing, nothing, 0, 1.1*Float64(maximum(mod_fft))),
    )
    expe_float = scatterlines!(normalize(float_fft, Inf), color=colors[1])
    expe_exact = scatterlines!(normalize(exact_fft, Inf), color=colors[3])
    expe_fixed16 = scatterlines!(normalize(fixed16_fft, Inf), color=colors[4])
    expe_fixed8 = scatterlines!(normalize(fixed8_fft, Inf), color=colors[5])
    res = scatterlines!(normalize(mod_fft, Inf), color=colors[2], marker=:+)
end

i = length(floatfft_testsizes) + 1
Legend(f[(i+1)÷2, (i+1)%2+1],
    [expe_float, expe_exact, expe_fixed16, expe_fixed8, res],
    ["Arduino FloatFFT", "Arduino ExactFFT", "Arduino Fixed16FFT", "Arduino Fixed8FFT", "Julia Float32 FFT"],
    tellwidth=false,
    tellheight=false
)

# resize_to_layout!(f)
save("results.png", f)
f

## Plotting time results.

sizes = [approxfft_testsizes, floatfft_testsizes, exactfft_testsizes, fixed16fft_testsizes, fixed8fft_testsizes]
labels = ["ApproxFFT", "FloatFFT", "ExactFFT", "Fixed16FFT",  "Fixed8FFT"]
times = Float32[approxfft_time; floatfft_time; exactfft_time; fixed16fft_time; fixed8fft_time] ./ 1000
order = invperm(sortperm(vec(maximum([approxfft_time floatfft_time exactfft_time fixed16fft_time fixed8fft_time], dims=1))))
groups = vcat([repeat([order[i]], length(t)) for (i,t) in enumerate(sizes)]...) 

positions = map(vcat(sizes...)) do x
    findmin(abs.(x .- approxfft_testsizes))[2]
end
colors = Makie.wong_colors()
fig = Figure(resolution=(1200, 800))
ax = Axis(fig[1, 1],
    title="FFT execution time.",
    xticks=(1:length(approxfft_testsizes), string.(approxfft_testsizes, base=10)),
    xlabel="Array size",
    ylabel="Execution time (ms)"
)

bp = barplot!(
    ax,
    positions,
    times,
    bar_labels=round.(times, digits=1),
    dodge=groups,
    color=colors[groups],
)
elements = [PolyElement(polycolor=colors[order[i]]) for i in 1:length(labels)]
title = "Implementation"

Legend(fig[1, 1],
    elements, labels, title,
    halign=:left, valign=:top,
    tellwidth=false, tellheight=false,
    margin=(10, 10, 10, 10),
)

save("execution_time_comparison.png", fig)
fig
