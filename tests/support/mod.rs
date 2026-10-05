use std::{path::Path, process::Command, sync::Arc, time::Duration};

use maki_agent::{
    AgentMode, ToolOutput,
    agent::tool_dispatch,
    tools::{CallOrigin, ToolContext, ToolRegistry},
};
use maki_lua::{PluginHost, PluginPermissions};
use serde_json::Value;

pub(super) const PLUGIN_NAME: &str = "maki-kanban";
const CHILD_TEST: &str = "MAKI_KANBAN_CHILD_TEST";
const CHILD_CWD: &str = "MAKI_KANBAN_CHILD_CWD";
pub(super) const TIMEOUT: Duration = Duration::from_secs(10);

pub(super) fn in_disposable_project(name: &str) -> bool {
    if std::env::var(CHILD_TEST).as_deref() == Ok(name) {
        let expected = std::env::var_os(CHILD_CWD).expect("child fixture path missing");
        assert_eq!(std::env::current_dir().unwrap(), Path::new(&expected));
        return true;
    }
    let project = tempfile::tempdir().unwrap();
    let output = Command::new(std::env::current_exe().unwrap())
        .args(["--exact", name, "--nocapture"])
        .env(CHILD_TEST, name)
        .env(CHILD_CWD, project.path())
        .current_dir(project.path())
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{name} failed:\n{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    false
}

pub(super) fn plugin_host() -> (Arc<ToolRegistry>, PluginHost) {
    plugin_host_with_permissions(PluginPermissions::trusted())
}

pub(super) fn plugin_host_with_permissions(
    permissions: PluginPermissions,
) -> (Arc<ToolRegistry>, PluginHost) {
    let registry = Arc::new(ToolRegistry::new());
    let host = PluginHost::new(Arc::clone(&registry)).unwrap();
    host.load_package(
        PLUGIN_NAME,
        Path::new(env!("CARGO_MANIFEST_DIR")),
        permissions,
        Default::default(),
    )
    .unwrap();
    (registry, host)
}

pub(super) fn run_lua(host: &PluginHost, source: &str) {
    host.send_run_init_lua(
        source.to_owned(),
        "kanban-integration-test.lua".to_owned(),
        Some(Path::new(env!("CARGO_MANIFEST_DIR")).to_path_buf()),
    )
    .unwrap();
}

pub(super) fn with_store(host: &PluginHost, source: &str) {
    let directory = tempfile::tempdir().unwrap();
    let path = serde_json::to_string(&directory.path().join("nested/tasks.json")).unwrap();
    run_lua(
        host,
        &format!(
            "local Store = require(\"kanban.store\")\nlocal path = {path}\nlocal store = Store.new(path)\n{source}"
        ),
    );
}

pub(super) fn dispatch_tool(context: &ToolContext, name: &str, input: &Value) -> String {
    let done = smol::block_on(tool_dispatch::run(
        String::new(),
        name,
        input,
        context,
        CallOrigin::Model,
    ));
    done.output.as_text()
}

pub(super) fn exec_tool(
    registry: &ToolRegistry,
    name: &str,
    input: Value,
) -> Result<String, String> {
    let entry = registry.get(name).expect("tool not registered");
    let invocation = entry
        .tool
        .parse(&input)
        .expect("tool input failed to parse");
    let context = maki_agent::tools::test_support::stub_ctx(&AgentMode::Build);
    smol::block_on(invocation.execute(&context))
        .output
        .map(|output| match output {
            ToolOutput::Plain(output) => output.text,
            other => panic!("unexpected tool output: {other:?}"),
        })
}

pub(super) fn tool_json(registry: &ToolRegistry, name: &str, input: Value) -> Value {
    serde_json::from_str(&exec_tool(registry, name, input).unwrap()).unwrap()
}

pub(super) fn persisted() -> Vec<u8> {
    std::fs::read(".maki/kanban.json").unwrap()
}

pub(super) fn store_path() -> String {
    std::fs::canonicalize(".maki/kanban.json")
        .unwrap_or_else(|_| std::env::current_dir().unwrap().join(".maki/kanban.json"))
        .to_string_lossy()
        .into_owned()
}
