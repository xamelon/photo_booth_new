import React, { useMemo, useState } from "react"
import { createRoot } from "react-dom/client"
import dagre from "dagre"
import {
  Background,
  Controls,
  Handle,
  MarkerType,
  MiniMap,
  Position,
  ReactFlow,
  ReactFlowProvider,
} from "@xyflow/react"

const roots = new Map()
const nodeWidth = 240
const baseNodeHeight = 126
const rowHeight = 24
const typeLabels = { message: "Message", action: "Action", input: "Input", condition: "Condition", end: "End" }

function nodeTypeClass(type) {
  return String(type || "custom").replace(/[^a-z0-9_-]/gi, "") || "custom"
}

function truncate(text, max = 72) {
  if (!text || text.length <= max) return text || ""
  return `${text.slice(0, max - 1)}…`
}

function nodeHeight(node) {
  if (node.type === "condition" && node.condition) return 72 + (node.condition.branches.length + 1) * rowHeight

  if (node.buttons?.length) {
    const textLines = Math.min(2, Math.ceil((node.label?.length || 1) / 58))
    return 96 + textLines * 18 + node.buttons.length * rowHeight
  }

  return baseNodeHeight
}

function layout(nodes, edges) {
  const graph = new dagre.graphlib.Graph()
  graph.setGraph({ rankdir: "LR", nodesep: 70, ranksep: 90, marginx: 30, marginy: 30 })
  graph.setDefaultEdgeLabel(() => ({}))

  for (const node of nodes) graph.setNode(node.id, { width: nodeWidth, height: nodeHeight(node.data) })
  for (const edge of edges) graph.setEdge(edge.source, edge.target)
  dagre.layout(graph)

  return nodes.map((node) => {
    const position = graph.node(node.id) || { x: 0, y: 0 }
    return { ...node, position: { x: position.x - nodeWidth / 2, y: position.y - nodeHeight(node.data) / 2 } }
  })
}

function buildGraph(viewer, selectedNodeId) {
  const selected = selectedNodeId ? viewer.nodes.find((node) => node.id === selectedNodeId) : null
  const connected = new Set(selected ? [...selected.incoming.map((e) => e.from), ...selected.outgoing.map((e) => e.to)] : [])

  const edges = viewer.nodes.flatMap((node) =>
    (node.outgoing || []).map((edge, index) => ({
      id: `${node.id}:${edge.to}:${index}`,
      source: node.id,
      target: edge.to,
      label: edge.label,
      type: "smoothstep",
      animated: node.type === "action",
      markerEnd: { type: MarkerType.ArrowClosed, width: 16, height: 16, color: "rgb(55 53 47 / 0.45)" },
    }))
  )

  const nodes = viewer.nodes.map((node) => ({
    id: node.id,
    type: "botNode",
    data: {
      ...node,
      selectionState:
        node.id === selectedNodeId ? "selected" : connected.has(node.id) ? "connected" : selected ? "dimmed" : "",
    },
    position: { x: 0, y: 0 },
    style: { width: nodeWidth },
  }))

  return { nodes: layout(nodes, edges), edges }
}

function FlowNode({ data }) {
  const typeClass = nodeTypeClass(data.type)
  const typeLabel = typeLabels[data.type] || data.type
  const isLive = data.metrics?.currentSessions > 0
  const hasIssues = data.validationIssues?.length > 0

  return (
    <div className={["flow-node-card", `flow-node-card--${typeClass}`, isLive ? "is-live" : "", data.selectionState ? `is-${data.selectionState}` : "", hasIssues ? "has-issues" : ""].filter(Boolean).join(" ")}>
      <Handle type="target" position={Position.Left} className="flow-node-handle" isConnectable={false} />
      <div className="flow-node-card-accent" />
      <div className="flow-node-card-body">
        <div className="flow-node-card-top">
          <span className="flow-node-type-badge">{typeLabel}</span>
          <div className="flow-node-flags">
            {isLive ? <span className="flow-node-flag flow-node-flag--live">live</span> : null}
            {hasIssues ? <span className="flow-node-flag flow-node-flag--warning">{data.validationIssues.length}</span> : null}
            {data.metrics?.errors > 0 ? <span className="flow-node-flag flow-node-flag--danger">{data.metrics.errors}</span> : null}
          </div>
        </div>
        <h3 className="flow-node-id">{data.id}</h3>
        {data.type === "condition" && data.condition ? (
          <ul className="flow-node-rows">
            {data.condition.branches.map((branch) => <li key={`${branch.when}:${branch.to}`}><span>{branch.when}</span><code>{branch.to}</code></li>)}
            <li className="is-default"><span>else</span><code>{data.condition.defaultTo}</code></li>
          </ul>
        ) : data.buttons?.length ? (
          <>
            <p className="flow-node-label">{truncate(data.label, 52)}</p>
            <ul className="flow-node-rows">
              {data.buttons.map((button) => <li key={`${button.label}:${button.to}`}><span>{button.label}</span><code>{button.to}</code></li>)}
            </ul>
          </>
        ) : (
          <p className="flow-node-label">{truncate(data.label)}</p>
        )}
      </div>
      <Handle type="source" position={Position.Right} className="flow-node-handle" isConnectable={false} />
    </div>
  )
}

function Metric({ label, value, alert }) {
  return <div><span>{label}</span><strong className={alert ? "is-alert" : ""}>{value}</strong></div>
}

function InspectorList({ title, items, empty }) {
  return (
    <div className="flow-inspector-list">
      <strong>{title}</strong>
      {items?.length ? <ul>{items.map((item, index) => <li key={index}>{item.name || item.label || item.to || item.from}<span>{item.to ? `→ ${item.to}` : item.from ? `from ${item.from}` : item.type || item.kind || ""}</span></li>)}</ul> : <p>{empty}</p>}
    </div>
  )
}

function FlowInspector({ node, onClose }) {
  const typeClass = nodeTypeClass(node.type)
  const typeLabel = typeLabels[node.type] || node.type

  return (
    <aside className="flow-viewer-inspector">
      <div className="flow-inspector-header">
        <span className={`flow-node-type-badge flow-node-card--${typeClass}`}>{typeLabel}</span>
        <button type="button" className="flow-inspector-close" onClick={onClose}>×</button>
      </div>
      <h3 className="flow-inspector-id">{node.id}</h3>
      <p className="flow-inspector-label">{node.label || "—"}</p>
      <div className="flow-inspector-metrics">
        <Metric label="Reached" value={node.metrics?.reachedUsers || 0} />
        <Metric label="Visits" value={node.metrics?.visits || 0} />
        <Metric label="Current" value={node.metrics?.currentSessions || 0} />
        <Metric label="Done" value={node.metrics?.completedUsers || 0} />
        <Metric label="Errors" value={node.metrics?.errors || 0} alert={node.metrics?.errors > 0} />
      </div>
      {node.condition ? <InspectorList title="Branches" items={[...node.condition.branches, { label: "else", to: node.condition.defaultTo }]} empty="No branches" /> : null}
      <InspectorList title="Incoming" items={node.incoming} empty="No incoming edges" />
      <InspectorList title="Outgoing" items={node.outgoing} empty="Terminal node" />
      <InspectorList title="Triggers" items={node.triggers} empty="No direct triggers" />
      {node.validationIssues?.length ? <InspectorList title="Validation" items={node.validationIssues.map((label) => ({ label }))} empty="No issues" /> : null}
    </aside>
  )
}

function BotFlowViewer({ viewer }) {
  const [selectedNodeId, setSelectedNodeId] = useState(null)
  const graph = useMemo(() => buildGraph(viewer, selectedNodeId), [viewer, selectedNodeId])
  const selectedNode = viewer.nodes.find((node) => node.id === selectedNodeId)

  return (
    <div className={`flow-viewer-shell${selectedNode ? " has-selection" : ""}`}>
      <div className="flow-viewer-canvas">
        <ReactFlow
          nodes={graph.nodes}
          edges={graph.edges}
          nodeTypes={{ botNode: FlowNode }}
          nodesDraggable={false}
          nodesConnectable={false}
          fitView
          fitViewOptions={{ padding: 0.18 }}
          minZoom={0.08}
          maxZoom={1.6}
          proOptions={{ hideAttribution: true }}
          onNodeClick={(_, node) => setSelectedNodeId(node.id)}
          onPaneClick={() => setSelectedNodeId(null)}
          defaultEdgeOptions={{ interactionWidth: 24, labelBgPadding: [6, 4], labelBgBorderRadius: 5 }}
        >
          <Background gap={20} size={1} color="rgb(55 53 47 / 0.06)" />
          <Controls showInteractive={false} />
          <MiniMap pannable zoomable nodeStrokeWidth={3} />
        </ReactFlow>
      </div>
      {selectedNode ? <FlowInspector node={selectedNode} onClose={() => setSelectedNodeId(null)} /> : null}
    </div>
  )
}

export function mountFlowViewer() {
  const target = document.getElementById("flow-viewer")
  const data = document.getElementById("flow-viewer-data")
  if (!target || !data || roots.has(target)) return

  const root = createRoot(target)
  root.render(<ReactFlowProvider><BotFlowViewer viewer={JSON.parse(data.textContent)} /></ReactFlowProvider>)
  roots.set(target, root)
}
