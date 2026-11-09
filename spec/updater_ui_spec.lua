package.path = "./?.lua;./?/init.lua;" .. package.path

local checks = 0
local function expect(condition, message)
    checks = checks + 1
    if not condition then error(message or ("check " .. checks .. " failed")) end
end

package.preload["ui/widget/confirmbox"] = function()
    return { new = function(_, value) return value end }
end
package.preload["ui/widget/infomessage"] = function()
    return { new = function(_, value) return value end }
end
package.preload["ui/widget/textviewer"] = function()
    return { new = function(_, value) return value end }
end
package.preload["ffi/blitbuffer"] = function()
    return { COLOR_BLACK = 0, COLOR_WHITE = 255 }
end
local shown_widget
local scheduled = {}
package.preload["ui/uimanager"] = function()
    return {
        show = function(_self, widget) shown_widget = widget end,
        close = function(_self, widget)
            if shown_widget == widget then shown_widget = nil end
        end,
        scheduleIn = function(_self, delay, callback)
            scheduled[#scheduled + 1] = { delay = delay, callback = callback }
        end,
        unschedule = function() end,
    }
end
package.preload["weread.ui.download_dialog"] = function()
    return { new = function(_, value) return value end }
end
package.preload["weread.lib.logger"] = function()
    return { warn = function() end, err = function() end }
end
package.preload["weread.lib.plugin_util"] = function()
    return {
        tr = function(value) return value end,
        T = function(template, ...)
            local values = { ... }
            return (template:gsub("%%(%d+)", function(index)
                return tostring(values[tonumber(index)] or "")
            end))
        end,
    }
end

local UpdaterUI = require("weread.ui.updater")
local state = { available_version = "0.7.0" }
local settings = {
    data_dir = "/tmp",
    get = function() return state end,
    set = function(_, _, value) state = value end,
    flush = function() end,
}
local core = require("weread.lib.updater"):new{
    settings = settings, current_version = "0.6.0", plugin_dir = "/tmp/weread.koplugin",
}
local ui = UpdaterUI:new{
    updater = core,
    settings = settings,
}

expect(ui:has_update(), "UI did not delegate update state")
expect(ui:available_version() == "0.7.0",
    "UI did not delegate available version")

local download_title = ui:_progress_title{
    stage = "downloading",
    current = 512 * 1024,
    total = 1024 * 1024,
}
expect(download_title:find("50%%") ~= nil,
    "download title did not show the real percentage")
expect(download_title:find("512 KB", 1, true) ~= nil
    and download_title:find("1.0 MB", 1, true) ~= nil,
    "download title did not show transferred bytes")
expect(ui:_progress_title{ stage = "verifying" }
    == "Verifying update package…", "verification stage title was wrong")
expect(ui:_progress_title{ stage = "extracting" }
    == "Extracting update package…", "extraction stage title was wrong")
expect(ui:_progress_title{ stage = "installing" }
    == "Installing update…", "installation stage title was wrong")

ui:_show_release{
    version = "0.7.0",
    notes = "First change\nSecond change",
}
expect(shown_widget.title == "New version available\nWeRead v0.6.0 → v0.7.0",
    "release notes viewer title was wrong")
expect(shown_widget.text == "First change\nSecond change"
    and shown_widget.buttons_table[1][1].text == "Close"
    and shown_widget.buttons_table[1][2].text == "Update now",
    "release notes viewer did not expose notes and install action")
expect(shown_widget.add_default_buttons == false and shown_widget.show_menu == false,
    "release viewer must not add navigation buttons")
shown_widget.buttons_table[1][1].callback()
expect(shown_widget == nil, "close button dismisses release notes")

local fetched = { version = "0.7.0", notes = "Release notes" }
core.fetch_release = function() return fetched end
ui._run_subprocess = function(_self, message, task, callback)
    expect(message == "Checking for updates…", "manual check shows progress")
    callback(task())
end
ui:check()
expect(shown_widget and shown_widget.text == fetched.notes, "manual check shows the new release")
local viewer = shown_widget
local another_ui = UpdaterUI:new{ updater = core, settings = settings }
expect(another_ui:_show_release(fetched) == nil and shown_widget == viewer,
    "two plugin instances displayed duplicate update dialogs")
viewer.buttons_table[1][1].callback()
ui:show_cached_update()
expect(shown_widget ~= nil, "manual cached update can reopen a dismissed release")
shown_widget.close_callback()
shown_widget = nil

fetched = { version = "0.6.0" }
ui:check()
expect(shown_widget and shown_widget.text:find("up to date", 1, true),
    "manual check reports the current version")
fetched = nil
ui:check()
expect(shown_widget and shown_widget.text:find("Update check failed", 1, true),
    "manual failure is reported")
shown_widget = nil

local installed
ui.install = function(_self, value) installed = value end
local install_release = { version = "0.9.0", notes = "Install now" }
ui:_show_release(install_release)
local install_button = shown_widget.buttons_table[1][2]
install_button.callback()
expect(shown_widget == nil, "install button must close the release viewer")
expect(another_ui:_show_release(install_release) == nil, "install must suppress concurrent dialogs")
scheduled[#scheduled].callback()
expect(installed == install_release, "install button did not use the displayed release")
local scheduled_count = #scheduled
install_button.callback()
expect(#scheduled == scheduled_count, "double activation scheduled two installs")

print(("updater_ui_spec: %d checks"):format(checks))
