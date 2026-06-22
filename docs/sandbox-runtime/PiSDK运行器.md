# Pi SDK 运行器

## Pi SDK 主线

Pi SDK 仍然是 SiriusX 的主执行路径，但它运行在 `siriusx-sandbox-runtime` 仓库和进程内，不直接进入可信控制面。

```
Control Worker (siriusx-control-plane)
  -> build RunSpec
  -> SandboxRuntimeClient.execute(runSpec)
       |
       v
SandboxRuntime (siriusx-sandbox-runtime)
  -> materialize workspace into temporary filesystem
  -> PiSdkRunner.run(runSpec)
  -> createAgentSession({
       cwd: sandboxWorkspaceDir,
       agentDir: sandboxAgentDir,
       sessionManager: SessionManager.inMemory(sandboxWorkspaceDir),
       authStorage: runScopedAuthStorage,
       modelRegistry,
       tools,
       customTools: [sandboxed bash]
     })
```

RPC 和 JSON mode 不作为主链路：

- SDK 用于生产执行，因为它提供类型、事件、工具和 sandbox 定制能力。
- RPC 可作为未来进程隔离 fallback。
- JSON mode 只用于调试和 smoke test。
- ACP 暂不进入主链路，未来可作为外部 agent runtime adapter。

Pi 官方文档带来的约束：

- Pi session 会保存为 JSONL session 文件，但 SiriusX 不能把这些文件当作 SaaS durable state；它们最多是 debug artifact。
- Pi 默认以当前进程权限运行。SiriusX 的阶段 0 策略是 **整个 Pi 进程进入一次性 sandbox runtime**，控制面不直接运行 Pi。
- Extensions 运行在 Pi 进程所在位置，因此 Agent Repo 自带 extension 也必须留在 sandbox runtime 内，并受同一套网络、文件和资源限制约束。

## PiSessionRunner 实现

`PiSdkRunner` 使用 `createAgentSession()`，但只在沙箱运行时内部暴露；控制面对外只依赖 `SandboxRuntimeClient`。

```typescript
interface SandboxRuntimeClient {
  execute(input: RunSpec): AsyncIterable<SandboxEvent>;
  abort?(runId: string): Promise<void>;
}
```

`RunSpec` 包含：

- `taskId`
- `runId`
- `baseWorkspaceRevision`
- `workspaceManifestRef`
- `prompt`
- `model`
- `capabilityToken`
- `historyWindow`
- `taskSummary`
- `attempt`

## 会话生命周期管理

Pi event 映射：

| Pi event | SiriusX event |
|---|---|
| `agent_start` | `run_started` |
| `message_update/text_delta` | `assistant_delta` |
| `message_update/thinking_delta` | `thinking_delta` |
| `tool_execution_start` | `tool_start` |
| `tool_execution_update` | `tool_update` |
| `tool_execution_end` | `tool_end` |
| `agent_end` | `turn_complete` |
| error / abort | `error` 或 `run_cancelled`（🚨 阶段 0 禁止使用 `task_error`，见 STAGE0_SPEC §7.3） |
