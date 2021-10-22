local harpoon = require("harpoon")
local log = require("harpoon.dev").log
local global_config = harpoon.get_global_settings()
local utils = require("harpoon.utils")

local M = {}
local tmux_windows = {}

local function create_terminal()
    log.trace("tmux: _create_terminal())")

    local window_id

    -- Create a new tmux window and store the window id
    local out, ret, _ = utils.get_os_command_output({
        "tmux",
        "new-window",
        "-P",
        "-F",
        "#{pane_id}",
    }, vim.loop.cwd())

    if ret == 0 then
        window_id = out[1]:sub(2)
    end

    if window_id == nil then
        log.error("tmux: _create_terminal(): window_id is nil")
        return nil
    end

    return window_id
end

-- Checks if the tmux window with the given window id exists
local function terminal_exists(window_id)
    log.trace("_terminal_exists(): Window:", window_id)

    local exists = false

    local window_list, _, _ = utils.get_os_command_output({
        "tmux",
        "list-windows",
    }, vim.loop.cwd())

    for _, line in pairs(window_list) do
        local window_info = utils.split_string(line, "@")[1]

        if string.find(window_info, window_id) then
            exists = true
        end
    end

    return exists
end

local function find_terminal(args)
    log.trace("tmux: _find_terminal(): Window:", args)

    if type(args) == "number" then
        args = { idx = args }
    end

    local window_handle = tmux_windows[args.idx]
    local window_exists

    if window_handle then
        window_exists = terminal_exists(window_handle.window_id)
    end

    if not window_handle or not window_exists then
        local window_id = create_terminal()

        if window_id == nil then
            return
        end

        window_handle = {
            window_id = window_id,
        }

        tmux_windows[args.idx] = window_handle
    end

    return window_handle
end

local function get_first_empty_slot()
    log.trace("_get_first_empty_slot()")
    for idx, cmd in pairs(harpoon.get_term_config().cmds) do
        if cmd == "" then
            return idx
        end
    end
    return M.get_length() + 1
end

M.gotoTerminal = function(idx)
    log.trace("tmux: gotoTerminal(): Window:", idx)
    local window_handle = find_terminal(idx)

    local _, _, _ = utils.get_os_command_output({
        "tmux",
        "select-window",
        "-t",
        "%" .. window_handle.window_id,
    }, vim.loop.cwd())
end

M.sendCommand = function(idx, cmd, ...)
    log.trace("tmux: sendCommand(): Window:", idx)
    local window_handle = find_terminal(idx)

    if type(cmd) == "number" then
        cmd = harpoon.get_term_config().cmds[cmd]
    end

    if global_config.enter_on_sendcmd then
        cmd = cmd .. "\n"
    end

    if cmd then
        log.debug("sendCommand:", cmd)

        -- Send the command to the given tmux window (creates it if it doesn't exist)
        local _, _, _ = utils.get_os_command_output({
            "tmux",
            "send-keys",
            "-t",
            "%" .. window_handle.window_id,
            string.format(cmd, ...),
        }, vim.loop.cwd())
    end
end

M.clear_all = function()
    log.trace("tmux: clear_all(): Clearing all tmux windows.")

    for _, window in ipairs(tmux_windows) do
        -- Delete the current tmux window
        local _, _, _ = utils.get_os_command_output({
            "tmux",
            "kill-window",
            "-t",
            "%" .. window.window_id,
        }, vim.loop.cwd())
    end

    tmux_windows = {}
end

M.get_length = function()
    log.trace("_get_length()")
    return table.maxn(harpoon.get_term_config().cmds)
end

M.valid_index = function(idx)
    if idx == nil or idx > M.get_length() or idx <= 0 then
        return false
    end
    return true
end

M.emit_changed = function()
    log.trace("_emit_changed()")
    if harpoon.get_global_settings().save_on_change then
        harpoon.save()
    end
end

M.add_cmd = function(cmd)
    log.trace("add_cmd()")
    local found_idx = get_first_empty_slot()
    harpoon.get_term_config().cmds[found_idx] = cmd
    M.emit_changed()
end

M.rm_cmd = function(idx)
    log.trace("rm_cmd()")
    if not M.valid_index(idx) then
        log.debug("rm_cmd(): no cmd exists for index", idx)
        return
    end
    table.remove(harpoon.get_term_config().cmds, idx)
    M.emit_changed()
end

M.set_cmd_list = function(new_list)
    log.trace("set_cmd_list(): New list:", new_list)
    for k in pairs(harpoon.get_term_config().cmds) do
        harpoon.get_term_config().cmds[k] = nil
    end
    for k, v in pairs(new_list) do
        harpoon.get_term_config().cmds[k] = v
    end
    M.emit_changed()
end

return M
