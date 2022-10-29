using CairoMakie, DataFrames, FFTW, FileIO, FixedPointNumbers, LibSerialPort, LinearAlgebra, Sixel, Statistics, Printf

plots_dir = mktempdir();

Base.display(fap::Makie.FigureAxisPlot) = display(fap.figure)
function Base.display(fig::Makie.Figure)
    fname = tempname(plots_dir) .* ".png"
    save(fname, fig)
    sixel_encode(stdout, load(fname))
end

list_ports()

##-- some utility functions

# ApproxFFT wants integers, and integers are encoded on two bytes on Arduino, so 
# we need to create a function that translates the output of `make_data` to 16-bits 
# integers.
function approxfft_prep(data)
    # We might as well use the full range of available data.
    mini, maxi = extrema(data)
    avg = mean(data)
    span = maxi - mini
    new_span = ((2^15 - 1)) - 1 # ApproxFFT does not like negative values.
    round.(Int16, (data .- avg) ./ span .* new_span)
end

# Convert the input to the correct fixed point representation.
function fixed16fft_prep(data)
    data = clamp.(data ./ maximum(data), Q0f15)
    reinterpret.(UInt16, reinterpret.(Int16, Q0f15.(data)))
end
function fixed8fft_prep(data)
    data = clamp.(data ./ maximum(data), Q0f7)
    reinterpret.(UInt8, reinterpret.(Int8, Q0f7.(data)))
end

##-- Defining the tests I want to run.

fft_tests = Dict([
    :approx_fft => (
        display="ApproxFFT",
        directory="ApproxFFT",
        header_datatype="int",
        retrieve_datatype=Int16,
        prep_func=approxfft_prep,
        n_read_type=Int16,
        header_size=256,
        test_sizes=[4, 8, 16, 32, 64, 128, 256],
    ),
    :exact_fft => (
        display="ExactFFT",
        directory="ExactFFT",
        header_datatype="float",
        retrieve_datatype=Float32,
        prep_func=identity,
        n_read_type=Int16,
        header_size=256,
        test_sizes=[4, 8, 16, 32, 64, 128, 256],
    ),
    :float_fft => (
        display="FloatFFT",
        directory="FloatFFT",
        header_datatype="float",
        retrieve_datatype=Float32,
        prep_func=identity,
        n_read_type=Int16,
        header_size=256,
        test_sizes=[4, 8, 16, 32, 64, 128, 256],
    ),
    :fixed16_fft => (
        display="Fixed16FFT",
        directory="Fixed16FFT",
        header_datatype="int16_t",
        retrieve_datatype=Q0f15,
        prep_func=fixed16fft_prep,
        n_read_type=Int16,
        header_size=256,
        test_sizes=[4, 8, 16, 32, 64, 128, 256],
    ),
    :fixed8_fft => (
        display="Fixed8FFT",
        directory="Fixed8FFT",
        header_datatype="int8_t",
        retrieve_datatype=Q0f7,
        prep_func=fixed8fft_prep,
        n_read_type=Int16,
        header_size=256,
        test_sizes=[4, 8, 16, 32, 64, 128, 256],
    ),])

##-- Settings for the Arduino
portname = "/dev/ttyACM0"
baudrate = 115200

function reset_arduino()
    LibSerialPort.open(portname, baudrate) do sp
        @info "Resetting Arduino"
        # Reset the Arduino
        set_flow_control(sp, dtr=SP_DTR_ON)
        sleep(0.1)
        set_flow_control(sp, dtr=SP_DTR_OFF)
        sp_flush(sp, SP_BUF_INPUT)
        sp_flush(sp, SP_BUF_OUTPUT)
    end
end

reset_arduino()
workdir = pwd()

##-- The test function
"""
Create the test data, N is the number of samples.
"""
function make_data(N)
    x = range(0, 12π, length=N)
    x, sin.(x) .+ sin.(2x) .+ sin.(3x)
end

##-- Plotting the test function just to be sure
testx, testy = make_data(2048)

lines(
    testx, testy,
    color=:red, # To match the original article
    axis=(
        xticksvisible=false,
        xticklabelsvisible=false,
        yticksvisible=false,
        yticklabelsvisible=false,
        title="Test function",
    )
)

save("test_signal.png", current_figure())

##-- Functions to set-up a test

function create_header_data(directory, header_datatype, prep_func, header_size)
    d = make_data(header_size)[2] |> prep_func
    open(joinpath(workdir, directory, "data.h"), write=true) do f
        write(f, "#ifndef H_DATA\n")
        write(f, "#define H_DATA\n")
        write(f, "$header_datatype data[] = {\n")
        for n ∈ d
            write(f, "$(repr(n)),\n")
        end
        write(f, "};\n")
        write(f, "#endif H_DATA\n")
    end
end

function upload_code(directory)
    build = joinpath(workdir, directory, "build")
    ino = joinpath(workdir, directory, directory * ".ino")

    build_command = `arduino-cli compile -b arduino:avr:uno -p $portname --build-path "$build" -u -v "$ino"`
    run(pipeline(build_command, stdout="log_arduino-cli.txt", stderr="log_arduino-cli.txt"))
end

function test_one_implementation(label, display, retrieve_datatype, n_read_type, test_sizes)
    time_result = zeros(size(test_sizes))
    n_points = sum(test_sizes)
    result = DataFrame(label=label, test_size=zeros(Int16, n_points), fft=zeros(n_points), index=zeros(Int16, n_points))
    debug = DataFrame(label=Symbol[], test_size=Int16[], fft=Float64[], index=Int16[])
    @info "Testing implementation" display 
    for (i, N) in enumerate(test_sizes)
        reset_arduino()
        LibSerialPort.open(portname, baudrate) do sp
            st = readline(sp)
            while st != "ready"
                @debug "Waiting for arduino to be ready"
                st = readline(sp)
                @debug "Arduino said" st
                sleep(0.05)
            end
            @info "Sending N" N
            write(sp, N)
            @debug "Awaiting confirmation"
            n_read = read(sp, n_read_type)
            @debug "Control" N n_read
            if n_read != N
                error("Received the wrong N : $n_read")
            end

            data = zeros(retrieve_datatype, n_read)
            s = readline(sp)
            while s != "done"
                @info "Debug received" s
                read!(sp, data)
                l = Symbol(string(label) * s)
                append!(debug, DataFrame(label=l, test_size=N, fft=data, index=collect(eachindex(data))))
                s = readline(sp)
            end

            read!(sp, data)
            @info "Read data."
            time = float(read(sp, UInt32))
            @info "Read time" time
            time_result[i] = time
            result_range = (N-first(test_sizes)+1):(2*N-first(test_sizes))
            result[result_range, :fft] .= data
            result[result_range, :index] .= eachindex(data)
            result[result_range, :test_size] .= N
            remaining = bytesavailable(sp)
            if remaining > 0
                s = read(sp)
                error("Communication failed. Remaining : $s")
            end
        end
    end
    time_result, result, debug
end

function measure_error(label, name, header_size, test_sizes)
    data = make_data(header_size)[2] .|> Float32
    true_fft = map(l -> fft(data[1:l]), test_sizes)
    sub_df = subset(fft_result, :label => ByRow(isequal(label)), view=true)
    gd = groupby(sub_df, :test_size)
    colors = Makie.wong_colors()
    f = Figure(resolution=(1200, 800))
    expe = nothing
    res = nothing
    dev = zeros(size(test_sizes))
    for (i, size) ∈ enumerate(test_sizes)
        target_result = normalize(abs.(true_fft[i][1:end÷2]), Inf)
        measured_result = normalize(gd[(test_size=size,)].fft[1:end÷2], Inf)
        dev[i] = sum(abs2.(target_result .- measured_result)) / size
        ax = Axis(f[(i+1)÷2, (i+1)%2+1],
            title="Sample size : $size",
            subtitle="MSE=$(round(dev[i], sigdigits=3))",
            yticklabelsvisible=false,
            # limits=(nothing, nothing, 0, 1.1*Float64(maximum(mod_fft))),
        )
        expe = scatterlines!(ax, measured_result, color=colors[1])
        res = scatterlines!(ax, target_result, color=colors[2], marker=:+)
    end
    i = length(test_sizes) + 1
    Legend(f[(i+1)÷2, (i+1)%2+1],
        [expe, res],
        [name, "Julia Float32 FFT"],
        tellwidth=false,
        tellheight=false
    )
    save("results_$name.png", f)
    display(f)
    dev
end

##-- Running all the tests

restrict = nothing # :fixed16_fft

fft_result = DataFrame(label=Symbol[], test_size=Int16[], fft=Float64[], index=Int16[])
fft_meta_results = DataFrame(label=Symbol[], test_size=Int16[], time=Float64[], error=Float64[])
fft_debug = DataFrame(label=Symbol[], test_size=Int16[], fft=Float64[], index=Int16[])

for (label, d) in fft_tests
    if !isnothing(restrict) && label != restrict
        continue
    end
    create_header_data(d.directory, d.header_datatype, d.prep_func, d.header_size)
    upload_code(d.directory)
    result = nothing 
    time_result = nothing
    debug = nothing
    try
        time_result, result, debug = test_one_implementation(label, d.display, d.retrieve_datatype, d.n_read_type, d.test_sizes)
        
    catch e
        if e isa ErrorException 
            @error "Test failed." e 
            @info "Retrying test for" label
            time_result, result, debug = test_one_implementation(label, d.display, d.retrieve_datatype, d.n_read_type, d.test_sizes)
        else
            rethrow(e)
        end
    else
    end
    append!(fft_result, result)
    append!(fft_debug, debug)
    dev = measure_error(label, d.display, d.header_size, d.test_sizes)
    append!(fft_meta_results, DataFrame(label=label, test_size=d.test_sizes, time=time_result./1e3, error=dev))
end

##-- Plotting time results.

position_numbers = sort(unique(fft_meta_results.test_size))
position_id = sortperm(position_numbers)
positions_dict = Dict([
  s=>p
  for (s,p) in zip(position_numbers, position_id)
])
positions = map(x->positions_dict[x], fft_meta_results.test_size)
sorted_labels = sort(fft_meta_results[fft_meta_results.test_size .== 256, :], :time).label
groups_dict = Dict([
    l=>i
    for (i,l) in enumerate(sorted_labels)
])
groups = getindex.(Ref(groups_dict), fft_meta_results.label)
colors = Makie.wong_colors()
bp = barplot(
    positions, fft_meta_results.time,
    bar_labels=round.(fft_meta_results.time, digits=1),
    dodge=groups,
    color=colors[groups],
    label_rotation=π/3,
    # flip_labels_at=(0, 25),
    # color_over_bar=:white,
    axis=(
        xticks=(position_id, string.(position_numbers, base=10)),
        xlabel="Input size",
        ylabel="Execution time (ms)",
        title="Comparing FFT implementations.",
        subtitle="Execution time comparison."
    ),
    figure=(
        resolution=(1000, 600),
    )
)
axislegend(
    current_axis(),
    [PolyElement(color = colors[g]) for g in getindex.(Ref(groups_dict), sorted_labels)],
    [fft_tests[l].display for l in sorted_labels],
    position=:lt,
)

fig = current_figure()

save("execution_time_comparison.png", fig)

##--

bp = barplot(
    positions, fft_meta_results.error,
    dodge=groups,
    color=colors[groups],
    fillto = 1e-16,
    axis=(
        xticks=(position_id, string.(position_numbers, base=10)),
        xlabel="Input size",
        ylabel="Error (MSE)",
        title="Comparing FFT implementations.",
        subtitle="Error comparison.",
        yscale=log10,
    ),
    figure=(
        resolution=(1000, 600),
    )
)
axislegend(
    current_axis(),
    [PolyElement(color = colors[g]) for g in getindex.(Ref(groups_dict), sorted_labels)],
    [fft_tests[l].display for l in sorted_labels],
    position=:lc,
)

fig = current_figure()

save("error_comparison.png", fig)
