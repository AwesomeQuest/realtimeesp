module realtimeesp

import CImGui as ig, ModernGL, GLFW
import CImGui.CSyntax: @c
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
	writedlm(f, ["Time [ms]" "Voltage [V]"], ',')
	counter = 0
	notify(peri, SERVICE_UUID, CHARACTERISTIC_UUID_TX) do data
		counter += 1
		jdata = JSON.parse(String(data))
		writedlm(f, Any[jdata["timestamp"] jdata["current"]], ',')
		@lock datalock push!(espdata, (jdata["timestamp"], jdata["current"]))
	end


	ig.set_backend(:GlfwOpenGL3)

	ctx = ig.CreateContext()
	io = ig.GetIO()
	io.ConfigFlags = unsafe_load(io.ConfigFlags) | ig.lib.ImGuiConfigFlags_DockingEnable
	io.ConfigFlags = unsafe_load(io.ConfigFlags) | ig.lib.ImGuiConfigFlags_ViewportsEnable
	style = ig.GetStyle()
	p_ctx =ImPlot.CreateContext()


	exit_application_bool = true
	first_frame = true
	ig.render(ctx; window_size=(1,1), window_title="Real Time ESP32 pin voltage", on_exit=() -> ImPlot.DestroyContext(p_ctx)) do
		!exit_application_bool && exit()

		DPI = ig.GetWindowDpiScale()
		ig.PushFont(C_NULL, 15.0f0DPI*unsafe_load(style.FontScaleDpi))
		if first_frame
			win = ig._current_window(Val{:GlfwOpenGL3}())
			GLFW.HideWindow(win)
		end
		first_frame = false

		@c ig.Begin("Plot Window", &exit_application_bool,
			ig.ImGuiWindowFlags_MenuBar |
			ig.ImGuiWindowFlags_NoCollapse)

		if (ig.BeginMenuBar())
			if (ig.BeginMenu("Tools"))
				@c ig.MenuItem("Show Plot Style Editor", "", &show_plot_style_editor)
				@c ig.MenuItem("Show ImGui Style Editor", "", &show_imgui_style_editor)
				ig.DragFloat("Window size##tools", style.FontScaleDpi, 0.001f0, 0.001f0, 4.0f0)
				ig.EndMenu();
			end
			ig.EndMenuBar();
		end


		if ImPlot.BeginPlot("Voltage", "Time", "Voltage", ig.ImVec2(-1, -1))
			xflags = ImPlot.ImPlotAxisFlags_None | ImPlot.ImPlotAxisFlags_AutoFit
			yflags = ImPlot.ImPlotAxisFlags_None | ImPlot.ImPlotAxisFlags_AutoFit
			ImPlot.SetupAxes("Time", "Voltage", xflags, yflags)
			@lock datalock begin
				ImPlot.PlotLine("data", first.(espdata), last.(espdata))
			end
			ImPlot.EndPlot()
		end
		
		ig.PopFont()
		ig.End()
	end

	disconnect(peri)
	return 0
end

end # module realtimeesp
