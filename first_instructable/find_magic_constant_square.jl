using CairoMakie

x = Float32.(-100:0.1:100)
true_value = x.^2

approx_sq(x::Float32, magic::UInt32) = begin
  i = reinterpret(UInt32, x)
  i <<= 1
  i -= UInt32(127<<23) - magic
  i &= UInt32((1<<31) - 1)
  reinterpret(Float32, i)
end

lines(x, true_value, label="x²", linewidth=4, axis=(xlabel="x",))
lines!(x, approx_sq.(x, zero(UInt32)), label="approx_sq(x)", linewidth=4)
axislegend(current_axis())
save("x_sq.png", current_figure())

function to_minimize(magic)
  approx_value = approx_sq.(x, magic)
  sum(abs2.(approx_value .- true_value))
end

possible_values = 0x00000000:0x007fffff
differences = zeros(length(possible_values))
Threads.@threads for (i,magic) ∈ collect(enumerate(possible_values))
  differences[i] = to_minimize(magic)
end
i,i_mini = findmin(differences)

differences = nothing


magic = possible_values[i_mini]
lines(x, true_value, label="x²", axis=(xlabel="x",), linewidth=4)
lines!(x, approx_sq.(x, magic), label="approx_sq_magic(x)", linewidth=4)
axislegend(current_axis())
save("x_sq_magic.png", current_figure())
current_figure()
