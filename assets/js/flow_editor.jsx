import React, { memo, useCallback, useEffect, useMemo, useState } from "react"
import { createRoot } from "react-dom/client"
import { DndContext, DragOverlay, closestCenter, useDroppable } from "@dnd-kit/core"
import { SortableContext, arrayMove, rectSortingStrategy, useSortable } from "@dnd-kit/sortable"
import { CSS } from "@dnd-kit/utilities"
import dagre from "dagre"
import { Background, Controls, Handle, MarkerType, MiniMap, Position, ReactFlow, ReactFlowProvider, useEdgesState, useNodesState, useReactFlow } from "@xyflow/react"

const roots = new Map()
const nodeWidth = 240
const typeLabels = { message: "Message", action: "Action", input: "Input", condition: "Condition", end: "End" }

function handleId(kind, index) {
  return index == null ? kind : `${kind}:${index}`
}

function rowHandles(node) {
  if (node.type === "condition") return [...(node.branches || []).map((_, index) => ({ id: handleId("branch", index), top: 72 + index * 24 })), { id: "default", top: 72 + (node.branches || []).length * 24 }]
  return []
}

function nodeHeight(node) {
  if (node.type === "condition") return 104 + (node.branches || []).length * 22
  if (node.type === "message" && rowsFromNode(node).length) return 98 + rowsFromNode(node).length * 20
  return 126
}

function labelFor(node) {
  if (node.type === "message") return node.text || ""
  if (node.type === "input") return node.prompt || node.input_key || ""
  if (node.type === "action") return node.action || ""
  if (node.type === "condition") return "branches"
  return node.type || ""
}

function edgesFor(definition) {
  return (definition.nodes || []).flatMap((node) => [
    ...(node.next ? [{ from: node.id, to: node.next, label: "next", kind: "next" }] : []),
    ...(node.default ? [{ from: node.id, to: node.default, label: "else", kind: "default" }] : []),
    ...flatButtons(node).map((b, index) => ({ from: node.id, to: b.to, label: b.label || "button", kind: "button", index })).filter((e) => e.to),
    ...(node.branches || []).map((b, index) => ({ from: node.id, to: b.to, label: b.when?.path || "branch", kind: "branch", index })).filter((e) => e.to),
  ])
}

function generatedPayload() {
  return `btn_${Math.random().toString(36).slice(2, 10)}`
}

function cleanButton(button) {
  return { label: button.label || "", payload: button.payload || generatedPayload(), to: button.to || "" }
}

function flatButtons(node) {
  return node.type === "message" && node.button_rows ? node.button_rows.flat() : node.buttons || []
}

function rowsFromNode(node) {
  if (node.button_rows) return node.button_rows.map((row) => row.map(cleanButton)).filter((row) => row.length)
  const perRow = Math.max(1, Math.min(5, Number(node.buttons_per_row) || 3))
  return chunk((node.buttons || []).map(cleanButton), perRow)
}

function withButtonRows(node, rows) {
  const cleanRows = rows.map((row) => row.map(cleanButton)).filter((row) => row.length)
  return { ...node, button_rows: cleanRows, buttons: cleanRows.flat() }
}

function normalizeDefinition(definition) {
  return {
    ...definition,
    nodes: (definition.nodes || []).map((node) => node.type === "message" ? withButtonRows(node, rowsFromNode(node)) : node),
  }
}

function withInitialPositions(definition) {
  if ((definition.nodes || []).every((node) => node.position)) return definition

  const edges = edgesFor(definition)
  const graph = new dagre.graphlib.Graph()
  graph.setGraph({ rankdir: "LR", nodesep: 70, ranksep: 90, marginx: 30, marginy: 30 })
  graph.setDefaultEdgeLabel(() => ({}))
  for (const node of definition.nodes || []) graph.setNode(node.id, { width: nodeWidth, height: nodeHeight(node) })
  for (const edge of edges) graph.setEdge(edge.from, edge.to)
  dagre.layout(graph)

  return {
    ...definition,
    nodes: (definition.nodes || []).map((node) => {
      if (node.position) return node
      const pos = graph.node(node.id) || { x: 0, y: 0 }
      return { ...node, position: { x: pos.x - nodeWidth / 2, y: pos.y - nodeHeight(node) / 2 } }
    }),
  }
}

function selectionState(definition, nodeId, selectedId) {
  if (!selectedId) return ""
  if (nodeId === selectedId) return "selected"

  const connected = new Set(
    edgesFor(definition)
      .filter((edge) => edge.from === selectedId || edge.to === selectedId)
      .flatMap((edge) => [edge.from, edge.to])
  )

  return connected.has(nodeId) ? "connected" : "dimmed"
}

function toReactNodes(definition, selectedId) {
  return (definition.nodes || []).map((node) => ({
    id: node.id,
    type: "editorNode",
    data: { node, selection: selectionState(definition, node.id, selectedId), start: node.id === definition.start_node_id },
    position: node.position || { x: 0, y: 0 },
    style: { width: nodeWidth, height: nodeHeight(node) },
  }))
}

function toReactEdges(definition) {
  return edgesFor(definition).map((edge) => ({
    id: `${edge.from}:${edge.kind}:${edge.index ?? 0}:${edge.to}`,
    source: edge.from,
    target: edge.to,
    sourceHandle: handleId(edge.kind, edge.index),
    label: edge.label,
    type: "default",
    data: edge,
    markerEnd: { type: MarkerType.ArrowClosed, width: 16, height: 16, color: "rgb(55 53 47 / 0.45)" },
  }))
}

function buttonPreviewRows(node) {
  let index = 0
  return rowsFromNode(node).map((row, rowIndex) => (
    <div key={rowIndex}>
      {row.map((button) => {
        const current = index++
        return <span className="flow-node-preview-button" key={button.payload || button.label}>{button.label}<Handle id={handleId("button", current)} type="source" position={Position.Bottom} className="flow-node-handle flow-node-handle--button" /></span>
      })}
    </div>
  ))
}

const EditorNode = memo(function EditorNode({ data }) {
  const node = data.node
  const rows = rowHandles(node)
  return (
    <div className={["flow-node-card", `flow-node-card--${node.type || "custom"}`, data.selection ? `is-${data.selection}` : "", data.start ? "is-live" : ""].filter(Boolean).join(" ")}>
      <Handle type="target" position={Position.Left} className="flow-node-handle" />
      {rows.length ? rows.map((row) => <Handle key={row.id} id={row.id} type="source" position={Position.Right} className="flow-node-handle flow-node-handle--row" style={{ top: row.top }} />) : node.type === "message" && flatButtons(node).length ? null : <Handle id="next" type="source" position={Position.Right} className="flow-node-handle" />}
      <div className="flow-node-card-accent" />
      <div className="flow-node-card-body">
        <div className="flow-node-card-top">
          <span className="flow-node-type-badge">{typeLabels[node.type] || node.type}</span>
          {data.start ? <span className="flow-node-flag flow-node-flag--live">start</span> : null}
        </div>
        <h3 className="flow-node-id">{node.id}</h3>
        <p className="flow-node-label">{labelFor(node) || "—"}</p>
        {node.type === "message" && rowsFromNode(node).length ? <div className="flow-node-button-preview">{buttonPreviewRows(node)}</div> : null}
        {node.type === "condition" ? <ul className="flow-node-rows">{(node.branches || []).map((b, i) => <li key={i}><span>{b.when?.path || "branch"}</span><code>{b.to}</code></li>)}<li><span>else</span><code>{node.default || "—"}</code></li></ul> : null}
      </div>
    </div>
  )
})

function TextField({ label, value, onChange, placeholder }) {
  return <label><span>{label}</span><input value={value || ""} placeholder={placeholder} onChange={(e) => onChange(e.target.value)} /></label>
}

function TextAreaField({ label, value, onChange, placeholder }) {
  return <label><span>{label}</span><textarea value={value || ""} placeholder={placeholder} onChange={(e) => onChange(e.target.value)} /></label>
}

function ButtonEditor({ rows, onChange }) {
  const [activeId, setActiveId] = useState(null)
  const [overId, setOverId] = useState(null)
  const activeButton = rows.flat().find((button) => button.payload === activeId)

  function update(rowIndex, index, patch) {
    onChange(replaceRowButton(rows, rowIndex, index, (button) => cleanButton({ ...button, ...patch })))
  }

  function finishDrag({ active, over }) {
    setActiveId(null)
    setOverId(null)
    if (!over) return
    const from = findButton(rows, active.id)
    if (!from) return

    const to = String(over.id).startsWith("row:")
      ? { row: Number(String(over.id).split(":")[1]), index: rows[Number(String(over.id).split(":")[1])]?.length || 0 }
      : findButton(rows, over.id)

    if (!to) return
    onChange(moveButton(rows, from, to))
  }

  return (
    <div className="button-editor">
      <div className="button-editor-header"><span>buttons</span><button type="button" className="secondary-button" onClick={() => onChange([...rows, [cleanButton({ label: "New button", to: "" })]])}>+ button</button></div>
      {rows.length ? <DndContext collisionDetection={closestCenter} onDragStart={(event) => { setActiveId(event.active.id); setOverId(event.active.id) }} onDragOver={(event) => setOverId(event.over?.id || null)} onDragCancel={() => { setActiveId(null); setOverId(null) }} onDragEnd={finishDrag}>{rows.map((row, rowIndex) => <ButtonRow key={rowIndex} row={row} rowIndex={rowIndex} activeId={activeId} overId={overId} update={update} remove={(index) => onChange(removeButton(rows, rowIndex, index))} />)}<DropRow id={`row:${rows.length}`} label="drop here for new row" showPlaceholder={String(overId) === `row:${rows.length}`} /><DragOverlay>{activeButton ? <ButtonPreview button={activeButton} /> : null}</DragOverlay></DndContext> : null}
      {rows.length === 0 ? <p>No buttons yet.</p> : null}
    </div>
  )
}

function ButtonRow({ row, rowIndex, activeId, overId, update, remove }) {
  const rowOver = String(overId) === `row:${rowIndex}`
  return <DropRow id={`row:${rowIndex}`} showPlaceholder={rowOver && !row.length}><SortableContext items={row.map((button) => button.payload)} strategy={rectSortingStrategy}><div className="button-preview editable">{row.map((button, index) => <React.Fragment key={button.payload}>{overId === button.payload && activeId !== button.payload ? <div className="button-insert-placeholder" /> : null}<SortableButton button={button} rowIndex={rowIndex} index={index} update={update} remove={remove} /></React.Fragment>)}{rowOver && row.length ? <div className="button-insert-placeholder" /> : null}</div></SortableContext></DropRow>
}

function DropRow({ id, label, showPlaceholder, children }) {
  const { setNodeRef, isOver } = useDroppable({ id })
  return <div ref={setNodeRef} className={["button-row-drop", isOver ? "is-over" : "", label ? "is-empty" : ""].filter(Boolean).join(" ")}>{showPlaceholder ? <div className="button-insert-placeholder" /> : children || label}</div>
}

function SortableButton({ button, rowIndex, index, update, remove }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: button.payload })
  return <div ref={setNodeRef} className={["preview-button-editor", isDragging ? "is-dragging" : ""].filter(Boolean).join(" ")} style={{ transform: CSS.Transform.toString(transform), transition }}><button type="button" className="button-drag-handle" {...attributes} {...listeners}>⋮⋮</button><input value={button.label || ""} placeholder="Button" onChange={(e) => update(rowIndex, index, { label: e.target.value })} /><button type="button" className="button-remove" onClick={() => remove(index)}>×</button></div>
}

function ButtonPreview({ button }) {
  return <div className="preview-button-editor is-overlay"><input readOnly value={button.label || ""} /></div>
}

function JsonField({ label, value, onChange }) {
  const [draft, setDraft] = useState(JSON.stringify(value || [], null, 2))
  const [error, setError] = useState("")
  useEffect(() => { setDraft(JSON.stringify(value || [], null, 2)); setError("") }, [value])
  return (
    <label className="json-field">
      <span>{label}</span>
      <textarea value={draft} onChange={(e) => setDraft(e.target.value)} onBlur={() => {
        try { onChange(JSON.parse(draft)); setError("") } catch (e) { setError(e.message) }
      }} />
      {error ? <em>{error}</em> : null}
    </label>
  )
}

function Inspector({ definition, selected, actions, updateNode, deleteNode, setStart, focusTarget }) {
  if (!selected) return <aside className="flow-editor-inspector empty"><h3>Select a node</h3><p>Drag nodes, connect handles, double-click an edge to delete it.</p></aside>

  return (
    <aside className="flow-editor-inspector">
      <div className="flow-inspector-header">
        <strong>{selected.id}</strong>
        <button type="button" className="secondary-button" onClick={() => setStart(selected.id)}>Set start</button>
      </div>
      <TextField label="id" value={selected.id} onChange={(id) => updateNode(selected.id, { id })} />
      <label><span>type</span><select value={selected.type || "message"} onChange={(e) => updateNode(selected.id, { type: e.target.value })}>{Object.keys(typeLabels).map((type) => <option key={type}>{type}</option>)}</select></label>
      {selected.type === "message" ? <><TextAreaField label="text" value={selected.text} onChange={(text) => updateNode(selected.id, { text })} /><label><span>VK keyboard</span><select value={selected.keyboard_mode || "inline"} onChange={(e) => updateNode(selected.id, { keyboard_mode: e.target.value })}><option value="inline">inline</option><option value="reply">reply</option></select></label></> : null}
      {selected.type === "input" ? <><TextField label="prompt" value={selected.prompt} onChange={(prompt) => updateNode(selected.id, { prompt })} /><TextField label="input_key" value={selected.input_key} onChange={(input_key) => updateNode(selected.id, { input_key })} /></> : null}
      {selected.type === "action" ? <label><span>action</span><select value={selected.action || ""} onChange={(e) => updateNode(selected.id, { action: e.target.value })}><option value="">choose action</option>{actions.map((action) => <option key={action}>{action}</option>)}</select></label> : null}
      {selected.type !== "end" && selected.type !== "condition" ? <TextField label="next" value={selected.next} placeholder="node id" onChange={(next) => updateNode(selected.id, { next })} /> : null}
      {selected.type === "message" ? <ButtonEditor rows={rowsFromNode(selected)} onChange={(rows) => updateNode(selected.id, withButtonRows(selected, rows))} /> : null}
      {selected.type === "condition" ? <><JsonField key={`${selected.id}:branches`} label="branches" value={selected.branches || []} onChange={(branches) => updateNode(selected.id, { branches })} /><TextField label="default" value={selected.default} onChange={(value) => updateNode(selected.id, { default: value })} /></> : null}
      {selected.type === "action" ? <JsonField key={`${selected.id}:params`} label="params" value={selected.params || {}} onChange={(params) => updateNode(selected.id, { params })} /> : null}
      <button type="button" className="danger-button" onClick={() => deleteNode(selected.id)}>Delete node</button>
      <details><summary>Flow JSON</summary><pre>{JSON.stringify(definition, null, 2)}</pre></details>
    </aside>
  )
}

function BotFlowEditor({ data }) {
  const initialDefinition = useMemo(() => withInitialPositions(normalizeDefinition(data.definition)), [data.definition])
  const [definition, setDefinition] = useState(initialDefinition)
  const [selectedId, setSelectedId] = useState(initialDefinition.start_node_id)
  const [nodes, setNodes, onNodesChange] = useNodesState(toReactNodes(initialDefinition, initialDefinition.start_node_id))
  const [edges, setEdges, onEdgesChange] = useEdgesState(toReactEdges(initialDefinition))
  const selected = (definition.nodes || []).find((node) => node.id === selectedId)
  const nodeTypes = useMemo(() => ({ editorNode: EditorNode }), [])
  const { setCenter } = useReactFlow()

  useEffect(() => {
    const form = document.getElementById("flow-editor-form")
    const field = document.getElementById("flow-editor-definition")
    if (!form || !field) return
    const submit = () => { field.value = JSON.stringify(serializeDefinition(definition, nodes), null, 2) }
    form.addEventListener("submit", submit)
    return () => form.removeEventListener("submit", submit)
  }, [definition, nodes])

  function sync(nextDefinition, nextSelectedId = selectedId) {
    setDefinition(nextDefinition)
    setNodes((nodes) => syncNodes(nodes, nextDefinition, nextSelectedId))
    setEdges(toReactEdges(nextDefinition))
  }

  function updateNode(oldId, patch) {
    const newId = patch.id || oldId
    const nextDefinition = {
      ...definition,
      start_node_id: definition.start_node_id === oldId ? newId : definition.start_node_id,
      nodes: (definition.nodes || []).map((node) => node.id === oldId ? { ...node, ...patch } : rewriteTargets(node, oldId, newId)),
    }
    sync(nextDefinition, newId)
    if (patch.id) setSelectedId(patch.id)
  }

  function addNode(type = "message") {
    const id = uniqueId(definition.nodes || [], type)
    const position = { x: 80, y: 80 }
    const node = { id, type, text: type === "message" ? "New message" : undefined, position }
    const nextDefinition = { ...definition, nodes: [...(definition.nodes || []), node] }
    setDefinition(nextDefinition)
    setNodes((nodes) => [...nodes, toReactNodes({ ...nextDefinition, nodes: [node] }, id)[0]])
    setSelectedId(id)
  }

  function deleteNode(id) {
    const nextDefinition = { ...definition, nodes: (definition.nodes || []).filter((node) => node.id !== id).map((node) => stripTarget(node, id)) }
    sync(nextDefinition, null)
    setSelectedId(null)
  }

  const connect = useCallback(({ source, target, sourceHandle }) => {
    if (!source || !target || source === target) return
    const nextDefinition = { ...definition, nodes: (definition.nodes || []).map((node) => node.id === source ? addTarget(node, target, sourceHandle) : node) }
    sync(nextDefinition)
  }, [definition, selectedId, nodes])

  const deleteEdge = useCallback((_, edge) => {
    const nextDefinition = { ...definition, nodes: (definition.nodes || []).map((node) => node.id === edge.source ? removeEdge(node, edge.data) : node) }
    sync(nextDefinition)
  }, [definition, selectedId, nodes])

  const dragStop = useCallback((_, node) => {
    setDefinition((definition) => ({ ...definition, nodes: (definition.nodes || []).map((item) => item.id === node.id ? { ...item, position: node.position } : item) }))
  }, [])

  const focusTarget = useCallback((id) => {
    const target = nodes.find((node) => node.id === id)
    if (target) setCenter(target.position.x + nodeWidth / 2, target.position.y + nodeHeight(target.data.node) / 2, { zoom: 1, duration: 250 })
    setSelectedId(id)
    setNodes((nodes) => nodes.map((item) => ({ ...item, data: { ...item.data, selection: selectionState(definition, item.id, id) } })))
  }, [definition, nodes, setCenter, setNodes])

  const selectNode = useCallback((_, node) => focusTarget(node.id), [focusTarget])

  return (
    <div className="flow-editor-shell">
      <div className="flow-editor-toolbar">
        <button type="button" className="secondary-button" onClick={() => addNode("message")}>+ Message</button>
        <button type="button" className="secondary-button" onClick={() => addNode("input")}>+ Input</button>
        <button type="button" className="secondary-button" onClick={() => addNode("action")}>+ Action</button>
        <button type="button" className="secondary-button" onClick={() => addNode("condition")}>+ Condition</button>
        <span className="flow-editor-hint">Drag nodes. Connect handles. Double-click edge to delete.</span>
      </div>
      <div className="flow-editor-canvas">
        <ReactFlow nodes={nodes} edges={edges} onNodesChange={onNodesChange} onEdgesChange={onEdgesChange} nodeTypes={nodeTypes} nodesDraggable nodesConnectable fitView fitViewOptions={{ padding: 0.18 }} minZoom={0.08} maxZoom={1.6} proOptions={{ hideAttribution: true }} defaultEdgeOptions={{ type: "default", interactionWidth: 24, labelBgPadding: [6, 4], labelBgBorderRadius: 6 }} onConnect={connect} onEdgeDoubleClick={deleteEdge} onNodeDragStop={dragStop} onNodeClick={selectNode}>
          <Background gap={20} size={1} color="rgb(55 53 47 / 0.06)" />
          <Controls />
          <MiniMap pannable zoomable nodeStrokeWidth={3} />
        </ReactFlow>
      </div>
      <Inspector definition={serializeDefinition(definition, nodes)} selected={selected} actions={data.actions || []} updateNode={updateNode} deleteNode={deleteNode} setStart={(id) => sync({ ...definition, start_node_id: id }, id)} focusTarget={focusTarget} />
    </div>
  )
}

function chunk(items, size) {
  const rows = []
  for (let index = 0; index < items.length; index += size) rows.push(items.slice(index, index + size))
  return rows
}

function findButton(rows, payload) {
  for (let row = 0; row < rows.length; row++) {
    const index = rows[row].findIndex((button) => button.payload === payload)
    if (index >= 0) return { row, index }
  }
}

function replaceRowButton(rows, rowIndex, index, fun) {
  return rows.map((row, currentRow) => currentRow === rowIndex ? replaceAt(row, index, fun) : row)
}

function removeButton(rows, rowIndex, index) {
  return rows.map((row, currentRow) => currentRow === rowIndex ? row.filter((_, itemIndex) => itemIndex !== index) : row).filter((row) => row.length)
}

function moveButton(rows, from, to) {
  const copy = rows.map((row) => [...row])
  const [button] = copy[from.row].splice(from.index, 1)
  const targetRow = copy[to.row] || (copy[to.row] = [])
  targetRow.splice(from.row === to.row && from.index < to.index ? to.index - 1 : to.index, 0, button)
  return copy.filter((row) => row.length)
}

function syncNodes(nodes, definition, selectedId) {
  const byId = new Map(nodes.map((node) => [node.id, node]))
  return (definition.nodes || []).map((node) => {
    const current = byId.get(node.id)
    return {
      ...(current || {}),
      id: node.id,
      type: "editorNode",
      data: { node, selection: selectionState(definition, node.id, selectedId), start: node.id === definition.start_node_id },
      position: current?.position || node.position || { x: 0, y: 0 },
      style: { width: nodeWidth, height: nodeHeight(node) },
    }
  })
}

function serializeDefinition(definition, nodes) {
  const positions = new Map(nodes.map((node) => [node.id, node.position]))
  return { ...definition, nodes: (definition.nodes || []).map((node) => ({ ...node, position: positions.get(node.id) || node.position })) }
}

function addTarget(node, target, sourceHandle = "next") {
  if (node.type === "end") return node
  const [kind, rawIndex] = String(sourceHandle || "next").split(":")
  const index = Number(rawIndex)
  if (kind === "button" && Number.isInteger(index)) return updateFlatButton(node, index, (button) => cleanButton({ ...button, to: target }))
  if (kind === "branch" && Number.isInteger(index)) return { ...node, branches: replaceAt(node.branches || [], index, (branch) => ({ ...branch, to: target })) }
  if (kind === "default") return { ...node, default: target }
  if (kind === "next") return { ...node, next: target }
  if (node.type === "message") return withButtonRows(node, [...rowsFromNode(node), [cleanButton({ label: target, to: target })]])
  if (node.type === "condition" && !node.default) return { ...node, default: target }
  if (node.type === "condition") return { ...node, branches: [...(node.branches || []), { when: { op: "exists", path: "TODO" }, to: target }] }
  return { ...node, next: target }
}

function replaceAt(items, index, fun) {
  return items.map((item, itemIndex) => itemIndex === index ? fun(item) : item)
}

function updateFlatButton(node, flatIndex, fun) {
  let current = 0
  const rows = rowsFromNode(node).map((row) =>
    row.map((button) => current++ === flatIndex ? fun(button) : button)
  )
  return withButtonRows(node, rows)
}

function removeEdge(node, edge) {
  if (edge.kind === "next") return { ...node, next: "" }
  if (edge.kind === "default") return { ...node, default: "" }
  if (edge.kind === "button") return updateFlatButton(node, edge.index, (button) => cleanButton({ ...button, to: "" }))
  if (edge.kind === "branch") return { ...node, branches: replaceAt(node.branches || [], edge.index, (branch) => ({ ...branch, to: "" })) }
  return node
}

function uniqueId(nodes, prefix) {
  const ids = new Set(nodes.map((node) => node.id))
  for (let i = 1; ; i++) if (!ids.has(`${prefix}_${i}`)) return `${prefix}_${i}`
}

function rewriteTargets(node, oldId, newId) {
  const patched = {
    ...node,
    next: node.next === oldId ? newId : node.next,
    default: node.default === oldId ? newId : node.default,
    branches: (node.branches || []).map((branch) => ({ ...branch, to: branch.to === oldId ? newId : branch.to })),
  }

  return node.type === "message"
    ? withButtonRows(patched, rowsFromNode(node).map((row) => row.map((button) => cleanButton({ ...button, to: button.to === oldId ? newId : button.to }))))
    : patched
}

function stripTarget(node, id) {
  return {
    ...node,
    next: node.next === id ? "" : node.next,
    default: node.default === id ? "" : node.default,
    ...withButtonRows(node, rowsFromNode(node).map((row) => row.map((button) => cleanButton(button.to === id ? { ...button, to: "" } : button)))),
    branches: (node.branches || []).map((branch) => branch.to === id ? { ...branch, to: "" } : branch),
  }
}

export function mountFlowEditor() {
  const target = document.getElementById("flow-editor")
  const data = document.getElementById("flow-editor-data")
  if (!target || !data || roots.has(target)) return
  const root = createRoot(target)
  root.render(<ReactFlowProvider><BotFlowEditor data={JSON.parse(data.textContent)} /></ReactFlowProvider>)
  roots.set(target, root)
}
