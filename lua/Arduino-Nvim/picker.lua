local M = {}

local cached_picker = nil
-- Define your fallback order here
local available_pickers = {
	{ id = "telescope", module = "telescope.pickers" },
	{ id = "snacks", module = "snacks" },
	{ id = "mini", module = "mini.pick" },
}

function M.getPicker()
	if cached_picker then
		return cached_picker
	end

	for _, picker in ipairs(available_pickers) do
		-- The underscore throws away the actual module table, keeping just the boolean
		local ok, _ = pcall(require, picker.module)
		if ok then
			cached_picker = picker.id
			return cached_picker
		end
	end
end

--- Core logic to install/update and refresh
---@param lib_name string
---@param outdated_libs table
---@param update_callback function
local function handle_selection(lib_name, outdated_libs, update_callback)
	local cmd = string.format('arduino-cli lib install "%s" > /dev/null 2>&1', lib_name)
	vim.fn.jobstart(cmd)

	if outdated_libs[lib_name] then
		vim.notify(string.format("Library '%s' updated successfully.", lib_name), vim.log.levels.INFO)
	else
		vim.notify(string.format("Library '%s' installed successfully.", lib_name), vim.log.levels.INFO)
	end

	-- Reopen/refresh the picker
	if type(update_callback) == "function" then
		update_callback()
	end
end

local pickers = {}

--- Snacks.nvim implementation
pickers.snacks = function(opts)
	local ok, snacks = pcall(require, "snacks")
	if not ok then
		return vim.notify("snacks.nvim not installed", vim.log.levels.ERROR)
	end

	snacks.picker({
		title = opts.title,
		items = opts.items,
		format = function(item)
			-- Snacks expects a format function to render custom tables
			return { { item.text } }
		end,
		confirm = function(picker, item)
			picker:close()
			if item then
				handle_selection(item.lib_name, opts.outdated_libs, opts.update_callback)
			end
		end,
	})
end

--- Mini.pick implementation
pickers.mini = function(opts)
	local ok, mini_pick = pcall(require, "mini.pick")
	if not ok then
		return vim.notify("mini.pick not installed", vim.log.levels.ERROR)
	end

	mini_pick.start({
		source = {
			name = opts.title,
			items = opts.items, -- mini.pick automatically looks for a 'text' field in tables
			choose = function(item)
				handle_selection(item.lib_name, opts.outdated_libs, opts.update_callback)
			end,
		},
	})
end

--- Telescope implementation
pickers.telescope = function(opts)
	local ok, telescope = pcall(require, "telescope.pickers")
	if not ok then
		return vim.notify("telescope.nvim not installed", vim.log.levels.ERROR)
	end

	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	telescope
		.new({}, {
			prompt_title = opts.title,
			finder = finders.new_table({
				results = opts.items,
				entry_maker = function(entry)
					if entry and entry.display_name and entry.lib_name then
						return {
							value = entry.display_name,
							display = entry.display_name, -- Show name with markers
							ordinal = entry.hidden_tag .. " " .. entry.lib_name, -- Use tag and lib_name for searchability
							lib_name = entry.lib_name, -- Store actual library name
						}
					else
						vim.notify("Error: entry or entry.display_name or entry.lib_name is nil", vim.log.levels.ERROR)
						return nil
					end
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				map("i", "<CR>", function()
					local selection = action_state.get_selected_entry()
					if selection then
						actions.close(prompt_bufnr)
						handle_selection(selection.lib_name, opts.outdated_libs, opts.update_callback)
					end
					return true
				end)
				return true
			end,
		})
		:find()
end

--- Main entry point
--- "telescope" | "snacks" | "mini"
---@param opts table { items = table, outdated_libs = table, update_callback = function }
function M.open(opts)
	opts.title = opts.title or "Available Arduino Libraries"

	local backend = M.getPicker()
	local picker_fn = pickers[backend]
	if picker_fn then
		picker_fn(opts)
	else
		vim.notify("Unknown picker backend: " .. tostring(backend), vim.log.levels.ERROR)
	end
end

return M
