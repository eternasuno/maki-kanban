mod support;

use std::{path::Path, sync::Arc};

use maki_agent::{AgentMode, tools::ToolContext};
use maki_lua::{Permission, PluginPermissions, UiAction, WinCommand, WinEvent};
use serde_json::{Value, json};

use support::{
    PLUGIN_NAME, TIMEOUT, dispatch_tool, exec_tool, in_disposable_project, persisted, plugin_host,
    plugin_host_with_permissions, run_lua, store_path, tool_json, with_store,
};

#[test]
fn package_registers_command_tools_and_stable_modules() {
    if !in_disposable_project("package_registers_command_tools_and_stable_modules") {
        return;
    }
    let (registry, host) = plugin_host();
    let snapshot = host.command_reader().load().clone();
    assert_eq!(snapshot.commands.len(), 1);
    let command = &snapshot.commands[0];
    assert_eq!(command.name.as_ref(), "/kanban");
    assert_eq!(command.plugin.as_ref(), PLUGIN_NAME);
    assert!(!command.description.is_empty());
    assert_eq!(command.max_args, 0);
    let mut names = registry.names();
    names.sort_unstable();
    assert_eq!(
        names
            .iter()
            .map(|name| name.as_ref())
            .collect::<Vec<&str>>(),
        [
            "task_create",
            "task_delete",
            "task_get",
            "task_list",
            "task_update"
        ]
    );
    run_lua(
        &host,
        r#"
        for _, name in ipairs({ "kanban.store", "kanban.tools", "kanban.ui", "kanban.ui.board", "kanban.ui.task" }) do
            local module = require(name)
            assert(type(module) == "table" and module == require(name), name)
        end
        assert(type(require("kanban.store").new) == "function")
        assert(type(require("kanban.tools").register) == "function")
        assert(type(require("kanban.ui").open) == "function")
        for _, name in ipairs({ "task_list", "task_get", "task_create", "task_update", "task_delete" }) do
            local tool = assert(maki.api.get_tool(name))
            assert(tool.name == name and tool.schema.type == "object")
        end
        "#,
    );
    let after = host.command_reader().load().clone();
    assert_eq!(after.generation, snapshot.generation);
    assert_eq!(after.commands.len(), 1);
    assert_eq!(registry.names().len(), 5);
    assert!(!Path::new(".maki").exists());
}

#[test]
fn store_batch_crud_defaults_id_reuse_and_reload() {
    if !in_disposable_project("store_batch_crud_defaults_id_reuse_and_reload") {
        return;
    }
    let (_, host) = plugin_host();
    with_store(
        &host,
        r#"
        assert(#assert(store:list()) == 0)
        local created = assert(store:create_many({ { title = "中文" }, { title = "second", description = "details" } }))
        assert(created["task-1"].id == "task-1" and created["task-1"].description == "")
        assert(created["task-1"].status == "todo" and created["task-2"].description == "details")
        local data = assert(maki.json.decode(assert(maki.fs.read(path))))
        assert(data.tasks["task-1"].id == nil and data.tasks["task-1"].title == "中文")
        assert(data.tasks["task-2"].status == "todo")
        local updated = assert(store:update_many({ ["task-1"] = { status = "doing" }, ["task-2"] = { title = "renamed", description = "" } }))
        assert(updated["task-1"].title == "中文" and updated["task-1"].description == "")
        assert(updated["task-2"].status == "todo" and updated["task-2"].description == "")
        local read = assert(Store.new(path):get_many({ "task-2", "task-1" }))
        assert(read["task-2"].title == "renamed" and read["task-1"].status == "doing")
        local deleted = assert(store:delete_many({ "task-1", "task-2" }))
        assert(deleted["task-1"].status == "doing" and deleted["task-2"].title == "renamed")
        assert(#assert(store:list()) == 0)
        assert(assert(store:create_many({ { title = "reused" }, { title = "kept" } }))["task-1"].title == "reused")
        assert(store:delete_many({ "task-1" }))
        assert(assert(store:create_many({ { title = "lowest hole" } }))["task-1"].title == "lowest hole")
        assert(maki.fs.write(path, '{"tasks":{"task-10":{"title":"external","status":"done"},"task-2":{"title":"two","status":"todo"}}}'))
        local listed = assert(store:list())
        assert(#listed == 2 and listed[1].id == "task-2" and listed[2].id == "task-10")
        assert(listed[2].description == "" and listed[2].status == "done")
        assert(assert(store:get_many({ "task-10" }))["task-10"].title == "external")
        local filled = assert(store:create_many({ { title = "first hole" }, { title = "next hole" } }))
        assert(filled["task-1"].title == "first hole" and filled["task-3"].title == "next hole")
        data = assert(maki.json.decode(assert(maki.fs.read(path))))
        assert(data.tasks["task-10"].description == "" and data.tasks["task-10"].id == nil)
        "#,
    );
}

#[test]
fn store_lists_mixed_string_ids_with_numeric_order_and_lexical_ties() {
    if !in_disposable_project("store_lists_mixed_string_ids_with_numeric_order_and_lexical_ties") {
        return;
    }
    let (_, host) = plugin_host();
    with_store(
        &host,
        r#"
        assert(store:create_many({ { title = "seed" } }))
        for _, expected in ipairs({
            { "task-2", "task-10", "", "alpha", "task-1x", "zeta" },
            { "task-002", "task-02", "task-2", "task-010", "task-10" },
        }) do
            local tasks = {}
            for _, id in ipairs(expected) do
                tasks[id] = { title = "Task " .. id, status = "todo" }
            end
            assert(maki.fs.write(path, assert(maki.json.encode({ tasks = tasks }))))
            local listed = assert(store:list())
            assert(#listed == #expected, "sorting must preserve arbitrary string IDs")
            for i, id in ipairs(expected) do
                assert(listed[i].id == id, "unexpected ID at " .. i .. ": " .. listed[i].id)
            end
        end
        "#,
    );
}

#[test]
fn store_invalid_and_missing_batches_preserve_file_bytes() {
    if !in_disposable_project("store_invalid_and_missing_batches_preserve_file_bytes") {
        return;
    }
    let (_, host) = plugin_host();
    with_store(
        &host,
        r#"
        assert(store:create_many({ { title = "one" }, { title = "two" } }))
        local before = assert(maki.fs.read(path))
        local function unchanged(value, err, expected)
            assert(value == nil and type(err) == "string" and err:find(expected, 1, true), tostring(err))
            assert(maki.fs.read(path) == before)
        end
        local value, err = store:create_many({ { title = "valid" }, { title = " " } })
        unchanged(value, err, "title must not be empty")
        for _, inputs in ipairs({ {}, { { title = "bad", description = false } }, { { title = "bad", status = "done" } }, { [2] = { title = "sparse" } } }) do
            value, err = store:create_many(inputs)
            unchanged(value, err, "")
        end
        for _, updates in ipairs({ {}, { ["task-1"] = {} }, { ["task-1"] = { unknown = true } }, { ["task-1"] = { status = "done" }, ["task-2"] = { status = "invalid" } }, { ["task-1"] = { title = "changed" }, missing = { title = "missing" } } }) do
            value, err = store:update_many(updates)
            unchanged(value, err, "")
        end
        for _, ids in ipairs({ {}, { "task-1", "task-1" }, { "task-1", "missing" }, { 1 } }) do
            value, err = store:get_many(ids)
            unchanged(value, err, "")
            value, err = store:delete_many(ids)
            unchanged(value, err, "")
        end
        assert(#assert(store:list()) == 2)
        "#,
    );
}

#[test]
fn store_corrupt_data_and_filesystem_write_failure_are_non_destructive() {
    if !in_disposable_project("store_corrupt_data_and_filesystem_write_failure_are_non_destructive")
    {
        return;
    }
    let (_, host) = plugin_host();
    with_store(
        &host,
        r#"
        assert(store:create_many({ { title = "preserved" } }))
        local before = assert(maki.fs.read(path))
        local blocker = maki.fs.joinpath(maki.fs.dirname(path), "blocker")
        assert(maki.fs.write(blocker, "not a directory"))
        store.dir = blocker
        for _, operation in ipairs({
            function() return store:create_many({ { title = "new" } }) end,
            function() return store:update_many({ ["task-1"] = { status = "done" } }) end,
            function() return store:delete_many({ "task-1" }) end,
        }) do
            local value, err = operation()
            assert(value == nil and err:find("could not create store directory:", 1, true), tostring(err))
            assert(maki.fs.read(path) == before and maki.fs.read(blocker) == "not a directory")
        end
        store.dir = maki.fs.dirname(path)
        for _, corrupt in ipairs({
            "{broken",
            "[]",
            '{"tasks":[{"title":"array","status":"todo"}]}',
            '{"tasks":{"task-1":{"title":"missing status"}}}',
            '{"tasks":{"task-1":{"title":"","status":"todo"}}}',
            '{"tasks":{"task-1":{"title":"bad","status":"unknown"}}}',
            '{"tasks":{"task-1":{"title":"bad","description":1,"status":"todo"}}}',
        }) do
            assert(maki.fs.write(path, corrupt))
            for _, operation in ipairs({
                function() return store:list() end,
                function() return store:get_many({ "task-1" }) end,
                function() return store:create_many({ { title = "new" } }) end,
                function() return store:update_many({ ["task-1"] = { title = "changed" } }) end,
                function() return store:delete_many({ "task-1" }) end,
            }) do
                local value, err = operation()
                assert(value == nil and err:find("invalid kanban store:", 1, true), tostring(err))
                assert(maki.fs.read(path) == corrupt)
            end
        end
        "#,
    );
}

#[test]
fn default_store_and_registered_tools_return_json_and_errors() {
    if !in_disposable_project("default_store_and_registered_tools_return_json_and_errors") {
        return;
    }
    let (registry, host) = plugin_host();
    run_lua(
        &host,
        r#"
        local store = require("kanban.store").new()
        assert(store.path == maki.fs.joinpath(maki.uv.cwd(), ".maki", "kanban.json"))
        assert(#assert(store:list()) == 0)
        "#,
    );
    assert_eq!(exec_tool(&registry, "task_list", json!({})).unwrap(), "[]");
    assert!(!Path::new(".maki").exists());
    let created = tool_json(
        &registry,
        "task_create",
        json!({"path": store_path(), "tasks": [{"title": "first"}, {"title": "second", "description": "details"}]}),
    );
    assert_eq!(
        created["task-1"],
        json!({"id": "task-1", "title": "first", "description": "", "status": "todo"})
    );
    assert_eq!(created.as_object().unwrap().len(), 2);
    let stored: Value = serde_json::from_slice(&persisted()).unwrap();
    assert!(stored["tasks"]["task-1"].get("id").is_none());
    let read = tool_json(
        &registry,
        "task_get",
        json!({"path": store_path(), "ids": ["task-2", "task-1"]}),
    );
    assert_eq!(read, created);
    let updated = tool_json(
        &registry,
        "task_update",
        json!({"path": store_path(), "tasks": {"task-1": {"status": "doing"}, "task-2": {"title": "renamed"}}}),
    );
    assert_eq!(updated["task-1"]["title"], "first");
    assert_eq!(updated["task-1"]["status"], "doing");
    assert_eq!(updated["task-2"]["description"], "details");
    let before = persisted();
    for (name, input, expected) in [
        (
            "task_create",
            json!({"path": store_path(), "tasks": [{"title": "valid"}, {"title": " "}]}),
            "error: title must not be empty",
        ),
        (
            "task_get",
            json!({"path": store_path(), "ids": ["task-1", "missing"]}),
            "error: task not found: missing",
        ),
        (
            "task_update",
            json!({"path": store_path(), "tasks": {"task-1": {"title": "changed"}, "missing": {"title": "missing"}}}),
            "error: task not found: missing",
        ),
        (
            "task_delete",
            json!({"path": store_path(), "ids": ["task-1", "missing"]}),
            "error: task not found: missing",
        ),
        (
            "task_update",
            json!({"path": store_path(), "tasks": {}}),
            "error: updates must not be empty",
        ),
        (
            "task_update",
            json!({"path": store_path(), "tasks": {"task-1": {}}}),
            "error: no fields to update",
        ),
        (
            "task_update",
            json!({"path": store_path(), "tasks": {"task-1": {"status": "invalid"}}}),
            "error: invalid status: invalid",
        ),
        (
            "task_update",
            json!({"path": store_path(), "tasks": {"task-1": {"unknown": true}}}),
            "error: unknown update field: unknown",
        ),
        (
            "task_update",
            json!({"path": store_path(), "tasks": "invalid"}),
            "error: updates must be an object",
        ),
    ] {
        assert_eq!(exec_tool(&registry, name, input).unwrap_err(), expected);
        assert_eq!(persisted(), before);
    }
    let listed = tool_json(&registry, "task_list", json!({}));
    assert!(listed.is_array());
    assert_eq!(listed[0], updated["task-1"]);
    assert_eq!(listed[1], updated["task-2"]);
    assert_eq!(
        tool_json(
            &registry,
            "task_delete",
            json!({"path": store_path(), "ids": ["task-1", "task-2"]})
        ),
        updated
    );
    assert_eq!(exec_tool(&registry, "task_list", json!({})).unwrap(), "[]");
    assert_eq!(
        tool_json(
            &registry,
            "task_create",
            json!({"path": store_path(), "tasks": [{"title": "reused"}]})
        )["task-1"]["id"],
        "task-1"
    );
    std::fs::write(".maki/kanban.json", "{broken").unwrap();
    for (name, input) in [
        ("task_list", json!({})),
        ("task_get", json!({"path": store_path(), "ids": ["task-1"]})),
        (
            "task_create",
            json!({"path": store_path(), "tasks": [{"title": "new"}]}),
        ),
        (
            "task_update",
            json!({"path": store_path(), "tasks": {"task-1": {"status": "done"}}}),
        ),
        (
            "task_delete",
            json!({"path": store_path(), "ids": ["task-1"]}),
        ),
    ] {
        assert!(
            exec_tool(&registry, name, input)
                .unwrap_err()
                .starts_with("error: invalid kanban store:")
        );
        assert_eq!(persisted(), b"{broken");
    }
}

#[test]
fn kanban_command_opens_and_q_closes_real_host_window() {
    if !in_disposable_project("kanban_command_opens_and_q_closes_real_host_window") {
        return;
    }
    let (_, host) = plugin_host();
    for _ in 0..2 {
        host.event_handle().run_command(
            Arc::from(PLUGIN_NAME),
            Arc::from("/kanban"),
            String::new(),
            0,
        );
        let action = host
            .ui_action_rx()
            .recv_timeout(TIMEOUT)
            .expect("/kanban did not open a window");
        match action {
            UiAction::OpenWin {
                event_tx,
                cmd_rx,
                focus,
                ..
            } => {
                assert!(focus);
                event_tx
                    .send(WinEvent::Key {
                        key: maki_lua::Key::parse("q").unwrap(),
                    })
                    .unwrap();
                loop {
                    if matches!(
                        cmd_rx
                            .recv_timeout(TIMEOUT)
                            .expect("q did not close /kanban"),
                        WinCommand::Close
                    ) {
                        break;
                    }
                }
            }
            UiAction::Flash(message) => panic!("/kanban failed: {message}"),
            _ => panic!("unexpected /kanban UI action"),
        }
    }
    assert!(!Path::new(".maki").exists());
}

#[test]
fn declared_permissions_support_real_tool_crud() {
    if !in_disposable_project("declared_permissions_support_real_tool_crud") {
        return;
    }
    assert_eq!(
        include_str!("../plugin.toml").trim(),
        "min_maki_version = \"0.6.0\"\n\n[permissions]\nfs_read = true\nfs_write = true",
        "update test grants when the package manifest changes"
    );
    let (registry, _host) =
        plugin_host_with_permissions(PluginPermissions::from_approved(["fs_read", "fs_write"]));
    let path = store_path();
    for (name, input, permission, mutable) in [
        ("task_list", json!({}), Permission::FsRead, false),
        (
            "task_get",
            json!({"ids": ["task-1"]}),
            Permission::FsRead,
            false,
        ),
        (
            "task_create",
            json!({"path": path, "tasks": [{"title": "scope"}]}),
            Permission::FsWrite,
            true,
        ),
        (
            "task_update",
            json!({"path": path, "tasks": {"task-1": {"status": "done"}}}),
            Permission::FsWrite,
            true,
        ),
        (
            "task_delete",
            json!({"path": path, "ids": ["task-1"]}),
            Permission::FsWrite,
            true,
        ),
    ] {
        let entry = registry.get(name).unwrap();
        assert_eq!(entry.tool.required_permission(), Some(permission));
        let invocation = entry.tool.parse(&input).unwrap();
        assert_eq!(
            smol::block_on(invocation.permission_scopes())
                .unwrap()
                .scopes,
            [path.as_str()]
        );
        if mutable {
            assert_eq!(invocation.mutable_path(), Some(Path::new(&path)));
        }
    }
    let created = tool_json(
        &registry,
        "task_create",
        json!({"path": store_path(), "tasks": [{"title": "permission check"}]}),
    );
    assert_eq!(created["task-1"]["status"], "todo");
    let updated = tool_json(
        &registry,
        "task_update",
        json!({"path": store_path(), "tasks": {"task-1": {"status": "done"}}}),
    );
    assert_eq!(updated["task-1"]["status"], "done");
    assert_eq!(
        tool_json(
            &registry,
            "task_get",
            json!({"path": store_path(), "ids": ["task-1"]})
        ),
        updated
    );
    assert_eq!(
        tool_json(
            &registry,
            "task_delete",
            json!({"path": store_path(), "ids": ["task-1"]})
        ),
        updated
    );
    assert_eq!(exec_tool(&registry, "task_list", json!({})).unwrap(), "[]");

    let path = store_path();
    let context = maki_agent::tools::test_support::stub_ctx(&AgentMode::Build);
    let context = ToolContext {
        registry: Arc::clone(&registry),
        ..context
    };
    let created = dispatch_tool(
        &context,
        "task_create",
        &json!({"path": path, "tasks": [{"title": "dispatcher"}]}),
    );
    let created: Value = serde_json::from_str(&created).unwrap();
    assert_eq!(created["task-1"]["title"], "dispatcher");
    let stored: Value = serde_json::from_slice(&persisted()).unwrap();
    assert_eq!(stored["tasks"]["task-1"]["title"], "dispatcher");
    let before = persisted();
    let plan = AgentMode::Plan(Path::new("PLAN.md").to_path_buf());
    let context = maki_agent::tools::test_support::stub_ctx(&plan);
    let context = ToolContext {
        registry: Arc::clone(&registry),
        ..context
    };
    let blocked = dispatch_tool(
        &context,
        "task_update",
        &json!({"path": path, "tasks": {"task-1": {"status": "done"}}}),
    );
    assert!(
        blocked.contains("write restricted to plan file"),
        "{blocked}"
    );
    assert_eq!(persisted(), before);
}

#[test]
fn board_and_task_views_execute_with_real_unicode_helpers() {
    if !in_disposable_project("board_and_task_views_execute_with_real_unicode_helpers") {
        return;
    }
    let (_, host) = plugin_host();
    run_lua(
        &host,
        r#"
        local Board = require("kanban.ui.board")
        local Task = require("kanban.ui.task")
        assert(require("kanban.ui.board") == Board)
        local task = { id = "task-1", title = "中文 task", description = "first\nsecond", status = "todo" }
        assert(maki.ui.display_width("中文") == 4)
        local board = Board.new(80, 24)
        assert(board:selected_task() == nil)
        assert(board:handle_key("?"))
        assert(board._state.help_open)
        assert(board:handle_key("<Esc>"))
        assert(not board._state.help_open)
        local detail = Task.new(task, 80, 24)
        local create = Task.new_create(80, 24)
        assert(detail.focused_field == "title" and detail.task.title == task.title)
        assert(create.creating and create.task.status == "todo" and create.task.title == "")
        for _, size in ipairs({ {80, 24}, {20, 8}, {1, 1}, {80, 24} }) do
            board:resize(size[1], size[2])
            detail:resize(size[1], size[2])
            create:resize(size[1], size[2])
            for _, view in ipairs({ board, detail, create }) do
                local lines = view:render()
                assert(type(lines) == "table" and #lines > 0)
            end
            assert(detail.offset >= 0 and detail.viewport >= 0)
        end
        assert(detail.task.description == "first\nsecond")
    "#,
    );
    assert!(!Path::new(".maki").exists());
}

#[cfg(target_os = "linux")]
#[test]
fn store_atomic_write_failure_preserves_existing_json() {
    use std::{io::Write, os::fd::AsRawFd};

    if !in_disposable_project("store_atomic_write_failure_preserves_existing_json") {
        return;
    }
    let (_, host) = plugin_host();
    let mut file = tempfile::tempfile().unwrap();
    let before =
        br#"{"tasks":{"task-1":{"title":"preserved","description":"original","status":"todo"}}}"#;
    file.write_all(before).unwrap();
    let path = format!("/proc/self/fd/{}", file.as_raw_fd());
    let lua_path = serde_json::to_string(&path).unwrap();
    run_lua(
        &host,
        &format!(
            r#"
            local store = require("kanban.store").new({lua_path})
            local before = assert(maki.fs.read(store.path))
            assert(assert(store:list())[1].title == "preserved")
            for _, operation in ipairs({{
                function() return store:create_many({{ {{ title = "new" }} }}) end,
                function() return store:update_many({{ ["task-1"] = {{ status = "done" }} }}) end,
                function() return store:delete_many({{ "task-1" }}) end,
            }}) do
                local value, err = operation()
                assert(value == nil and err:find("could not write store:", 1, true), tostring(err))
                assert(maki.fs.read(store.path) == before)
            end
            "#
        ),
    );
    assert_eq!(std::fs::read(path).unwrap(), before);
}
