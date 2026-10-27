extends Area3D
# ============================================================
# caja.gd
# Va en: nodo raíz (Area3D) de caja.tscn
# ============================================================

@export var distancia_maxima: float = 4.0
## 1.0 = la caja está justo en el centro de la mira. 0.8 tolera algo de desvío.
@export var alineacion_minima: float = 0.8

var jugador: CharacterBody3D = null
var esta_agarrada: bool = false


func _ready() -> void:
	add_to_group("cajas")
	aplicar_dimensiones_y_color()


func aplicar_dimensiones_y_color() -> void:
	var mesh = get_node_or_null("MeshInstance3D")
	if not mesh:
		mesh = MeshInstance3D.new()
		mesh.name = "MeshInstance3D"
		add_child(mesh)

	var b = BoxMesh.new()
	b.size = Vector3(0.9, 0.85, 1.2)
	mesh.mesh = b
	mesh.position = Vector3(0, 0.425, 0)

	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.48, 0.28) # Color cartón
	mesh.material_override = material

	var col = get_node_or_null("CollisionShape3D")
	if not col:
		col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		add_child(col)

	if not col.shape:
		col.shape = BoxShape3D.new()
	if col.shape is BoxShape3D:
		col.shape.size = Vector3(0.9, 0.85, 1.2)
	col.position = Vector3(0, 0.425, 0)


func _unhandled_input(event: InputEvent) -> void:
	# Durante la transición no se puede recoger nada
	if esta_agarrada or GameManager.en_transicion or get_tree().paused:
		return
	if not _es_tecla_de_recoger(event):
		return

	if not jugador:
		jugador = get_tree().root.find_child("Player", true, false) as CharacterBody3D
	if not jugador:
		return

	var camara := jugador.get_node_or_null("Camera3D") as Camera3D
	if camara == null:
		return

	# Solo se puede llevar UNA caja a la vez: primero hay que entregarla en el camión
	var caja_mano = camara.get_node_or_null("CajaEnMano")
	if caja_mano and caja_mano.visible:
		return

	# Solo reacciona UNA caja por pulsación: la que estás mirando
	if not _soy_la_mejor_candidata(camara):
		return

	get_viewport().set_input_as_handled()
	_recoger(camara, caja_mano)


func _es_tecla_de_recoger(event: InputEvent) -> bool:
	var tecla := event as InputEventKey
	if tecla == null:
		return false
	return tecla.pressed and not tecla.echo and tecla.keycode == KEY_E


func _soy_la_mejor_candidata(camara: Camera3D) -> bool:
	var mirada: Vector3 = -camara.global_transform.basis.z
	var mejor: Node = null
	var mejor_puntaje: float = -INF

	for otra in get_tree().get_nodes_in_group("cajas"):
		if otra.esta_agarrada:
			continue

		var hacia_caja: Vector3 = (otra.global_position + Vector3(0, 0.425, 0)) - camara.global_position
		var distancia: float = hacia_caja.length()
		if distancia > distancia_maxima or distancia < 0.001:
			continue

		var alineacion: float = hacia_caja.normalized().dot(mirada)
		if alineacion < alineacion_minima:
			continue

		# Gana la más centrada en la mira; a igualdad, la más cercana
		var puntaje: float = alineacion - distancia * 0.01
		if puntaje > mejor_puntaje:
			mejor_puntaje = puntaje
			mejor = otra

	return mejor == self


func _recoger(camara: Camera3D, caja_mano) -> void:
	esta_agarrada = true
	remove_from_group("cajas")

	# 1. Mostrar la caja en las manos del jugador
	if caja_mano:
		if jugador.has_method("construir_caja_y_manos_fov"):
			jugador.construir_caja_y_manos_fov()
		caja_mano.visible = true
	print("📦 ¡Caja recogida! Llévala al camión y pulsa E.")

	# 2. Quitarla del estante (ya NO cuenta para el mes: cuenta al entregarla)
	hide()
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	queue_free()
