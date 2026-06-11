# SRE 速成笔记 — 以本 lab 为教材

> SRE 一句话:开发保证"功能对",SRE 保证"一直活着、出事能快速恢复"。
> 五大环节:发布 → 观测 → 告警 → 事故响应 → 容量,外加贯穿一切的自动化。

## 环节 × 工具映射

| 环节 | 要回答的问题 | 工具(lab 对应物) |
|---|---|---|
| 发布 | 上线不炸?炸了 30 秒回去? | Deployment 滚动更新 / `rollout undo`;Jenkins / GitHub Actions |
| 观测 | 系统现在什么状态? | 指标 Prometheus;日志 ELK / `kubectl logs`;链路 OpenTelemetry(了解) |
| 告警 | 出事谁第一时间知道? | PromQL rules + Alertmanager;告什么由 SLO 决定 |
| 事故响应 | 半夜被叫起来先干什么? | on-call、runbook、先止血(回滚/扩容/限流/降级)、postmortem |
| 容量 | 流量翻倍会不会跪? | requests/limits、HPA、Locust 压测 |
| 自动化 | 消灭重复 | Bash/Python、K8s 调和循环、Terraform(下阶段) |

## 组件清单(本 lab)

**打包与运行**
- Docker:代码+依赖打成镜像,处处一致。lab 用多阶段构建(JDK build → JRE run)。
- Kubernetes:声明期望状态,系统不停把现实掰成声明的样子(调和循环)= 自带自愈。
- k3d/k3s:轻量 K8s 跑在 Docker 里,练手用,行为同真集群。
- kubectl:四件套 `get / describe / logs / rollout` 占日常 90%。

**K8s 对象**
- Pod:最小单元,牲口不是宠物,死了换不修。
- Deployment:管副本数 + 升级策略;`maxUnavailable: 0` 升级不减容量;`rollout undo` 一键回滚。
- Service:稳定虚拟 IP + 集群内 DNS,只把流量给"就绪"的 pod。
- readiness vs liveness(高频面试):readiness="能接客吗"→摘流量;liveness="卡死了吗"→重启。配反 = 重启风暴。
- requests/limits:requests=调度预留;limits=红线 —— 内存超限 OOMKilled,CPU 超限节流变慢。

**观测(kube-prometheus-stack)**
- Prometheus:pull 模式时序库 + PromQL。
  - QPS: `rate(http_server_requests_seconds_count[5m])`
  - p95: `histogram_quantile(0.95, rate(http_server_requests_seconds_bucket[5m]))`
  - 5xx 率: `sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))`
- Actuator/Micrometer:应用自己暴露 /actuator/prometheus(QPS、延迟直方图、JVM)。
- ServiceMonitor:声明式抓取名单(靠 label 选中 Service),新 pod 自动纳管。
- Grafana:看板。四个黄金信号:流量、延迟、错误率、饱和度。
- Alertmanager:告警的路由/去重/分组/静默 —— Prometheus 判断出事,它决定通知谁。
- node-exporter(机器层)+ kube-state-metrics(K8s 对象层)+ 应用指标(应用层)= 三层观测,排障自上而下切。
- Helm:K8s 的包管理器,一条命令装全家桶。

**压测**
- Locust:Python 写用户行为,模拟并发;让看板有真曲线 + 找容量拐点。

## 事故响应肌肉记忆
```
报警 → 确认影响面(哪个 SLO 在烧)
     → 先止血再找根因:rollback / 扩容 / 限流 / 降级
     → 止血后:logs / describe / events / 看板对时间线
     → postmortem:时间线、根因、为何没早发现、action items(blameless)
```
```bash
kubectl get pods
kubectl describe pod <p>        # Events: OOMKilled? probe fail?
kubectl logs <p> --previous     # 死前最后一句
kubectl rollout undo deployment/<d>
```

## SLO 一分钟
SLI=量出来的;SLO=承诺的目标;**error budget = 1−SLO = 本月允许烂的额度**。
预算没烧完→放心发布;烧完→冻结发布还稳定性的债。它是"快 vs 稳"的合约。

## 本 lab 已完成 / 待办
- [x] Spring Boot video-origin(/api/videos、/slow、/error、/hog 三个故障杠杆)
- [x] 多阶段 Dockerfile;k3d 双节点集群;Deployment+Service+probes+limits
- [x] 滚动发布 + 一次真实排障(Spring 组件扫描 404)
- [x] kube-prometheus-stack + ServiceMonitor(targets up)
- [x] Grafana 看板(QPS/p95/5xx/CPU/Mem/restarts)
- [x] Locust 压测
- [x] 事故演练 1:坏版本 → 5xx spike → rollout undo;runbook+postmortem
- [x] 事故演练 2:调低 memory limit + /api/hog → OOMKilled → 诊断;runbook+postmortem
- [ ] Nginx edge cache 层(v2,贴 Video/Edge 主题)
- [ ] push GitHub + README(架构图+看板截图)
