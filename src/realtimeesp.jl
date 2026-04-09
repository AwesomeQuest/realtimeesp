module realtimeesp

import CImGui as ig, ModernGL, GLFW
import ImPlot
using SimpleBLE
using JSON, DelimitedFiles
using Dates

function (@main)(ARGS)

	samplerate = 500
	if length(ARGS) > 0
		samplerate = parse(Int, ARGS[1])
	end
	adapter = get_adapter(0)
	peri = find_peripheral(adapter) do id
		occursin("SiNW", id)
	end
	connect(peri)
	SERVICE_UUID				= "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
	CHARACTERISTIC_UUID_TX		= "beb5483e-36e1-4688-b7f5-ea07361b26a8"
	CHARACTERISTIC_UUID_RX		= "6d68ef76-79f6-4b8a-bf9d-05fc906b8290"
	CHARACTERISTIC_UUID_CONFIG	= "3c3d5e6f-7a8b-4c9d-9e0f-1a2b3c4d5e6f"

	@info "Writing Commands"
	write_request(peri, SERVICE_UUID, CHARACTERISTIC_UUID_RX, JSON.json("cmd" => "start"))
	write_request(peri, SERVICE_UUID, CHARACTERISTIC_UUID_RX, JSON.json(Dict("cmd"=>"set_rate", "rate"=>samplerate)))

	sleep(0.5)

	@info "Setting up data stream"
	currtime = replace(string(now()), ':'=>"", '-'=>"")
	espdata = Tuple{Float64, Float64}[]
	datalock = ReentrantLock()
	f = open("logs_$currtime.csv", "w")
	writedlm(f, ["Time [ms]" "Currrent"], ',')
	counter = 0
	notify(peri, SERVICE_UUID, CHARACTERISTIC_UUID_TX) do data
		counter += 1
		jdata = JSON.parse(String(data))
		writedlm(f, Any[jdata["timestamp"] jdata["current"]], ',')
		@lock datalock push!(espdata, (jdata["timestamp"], jdata["current"]))
	end

	
	ig.set_backend(:GlfwOpenGL3)

	ctx = ig.CreateContext()
	p_ctx =ImPlot.CreateContext()

	ig.render(ctx; on_exit=() -> ImPlot.DestroyContext(p_ctx)) do
		ig.Begin("Plot Window")
		ImPlot.SetNextAxesLimits(0.0,1000,0.0,1.0, ig.ImGuiCond_Once)
		if ImPlot.BeginPlot("Foo", "x1", "y1", ig.ImVec2(-1, 300))
			@lock datalock begin
				iv_xflags = ImPlot.ImPlotAxisFlags_None | ImPlot.ImPlotAxisFlags_AutoFit
				iv_yflags = ImPlot.ImPlotAxisFlags_None | ImPlot.ImPlotAxisFlags_AutoFit
				ImPlot.SetupAxes("Time", "Voltage", iv_xflags, iv_yflags)
				ImPlot.PlotLine("data", first.(espdata), last.(espdata))
			end
			ImPlot.EndPlot()
		end
		ig.End()
	end

	disconnect(peri)
	return 0
end

end # module realtimeesp
