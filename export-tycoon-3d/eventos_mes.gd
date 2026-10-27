extends CanvasLayer
# ============================================================
# eventos_mes.gd
# Va en: res://eventos_mes.gd
# Minieventos AUTOMÁTICOS al inicio de cada mes: barras de cine,
# cartel con narración y efectos en el escenario. Sin decisiones.
# ============================================================

const ALTO_BARRA: float = 80.0

const EVENTOS: Dictionary = {
	1: {
		"titulo": "MES 1  -  PRIMER DÍA",
		"texto": "Bienvenido al almacén. Cada mes debes ordenar y despachar todas las cajas. Tus decisiones construirán tu Honor.",
		"efecto": "_ef_bienvenida",
		"duracion": 6.5,
	},
	2: {
		"titulo": "MES 2  -  TORMENTA",
		"texto": "Una tormenta golpea el techo del almacén. Hay goteras sobre las estanterías: la mercadería corre peligro.",
		"efecto": "_ef_lluvia",
		"duracion": 7.0,
	},
	3: {
		"titulo": "MES 3  -  CARGA ESPECIAL",
		"texto": "Llegan lotes de mercadería frágil y pesada. Los camiones hacen temblar el piso del almacén.",
		"efecto": "_ef_carga_pesada",
		"duracion": 6.0,
	},
	4: {
		"titulo": "MES 4  -  APAGÓN",
		"texto": "Falla eléctrica en la planta. El almacén opera solo con las luces de emergencia.",
		"efecto": "_ef_apagon",
		"duracion": 7.0,
	},
	5: {
		"titulo": "MES 5  -  ENVÍO EXPRÉS",
		"texto": "Alerta: un camión de prioridad máxima espera en el muelle. Cada minuto cuenta.",
		"efecto": "_ef_express",
		"duracion": 6.0,
	},
	6: {
		"titulo": "MES 6  -  AUDITORÍA SORPRESA",
		"texto": "Los auditores recorren el almacén fotografiando cada rincón. Nada pasa desapercibido.",
		"efecto": "_ef_auditoria",
		"duracion": 6.5,
	},
	7: {
		"titulo": "MES 7  -  MANTENIMIENTO",
		"texto": "Soldadores reparan las estanterías. Chispas y polvo flotan por los pasillos.",
		"efecto": "_ef_mantenimiento",
		"duracion": 6.5,
	},
	8: {
		"titulo": "MES 8  -  TEMPORADA ALTA",
		"texto": "Llega la temporada alta: los paquetes no dejan de entrar. El ritmo se acelera.",
		"efecto": "_ef_temporada",
		"duracion": 6.0,
	},
	9: {
		"titulo": "MES 9  -  ALERTA ESTRUCTURAL",
		"texto": "Las estanterías vibran bajo el peso acumulado. Algo no está bien...",
		"efecto": "_ef_alerta",
		"duracion": 7.0,
	},
	10: {
		"titulo": "MES 10  -  NUEVO MONTACARGAS",
		"texto": "Un montacargas recorre los pasillos: la nueva flota de carga ya está en operación.",
		"efecto": "_ef_montacargas",
		"duracion": 7.0,
	},
	11: {
		"titulo": "MES 11  -  EXPORTACIÓN",
		"texto": "Llegan cajas de exportación. Cada una pasa por el escáner de etiquetado antes de despachar.",
		"efecto": "_ef_exportacion",
		"duracion": 6.5,
	},
	12: {
		"titulo": "MES 12  -  GRAN FINAL",
		"texto": "Último mes del año. Se evalúa todo lo que has hecho en el almacén.",
		"efecto": "_ef_final",
		"duracion": 7.5,
	},
}

var _barra_sup: ColorRect
var _barra_inf: ColorRect
var _flash: ColorRect
var _barra_scan: ColorRect
var _cartel: MarginContainer
var _label_titulo: Label
var _label_texto: Label

var _evento_id: int = 0
var _temporales: Array[Node] = []
var _energia_normal: float = 1.0


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_construir_interfaz()


# ------------------------------------------------------------
# INTERFAZ (se construye por código)
# ------------------------------------------------------------
func _construir_interfaz() -> void:
	# Destello de pantalla completa
	_flash = ColorRect.new()
	_flash.color = Color.WHITE
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Línea de escáner que baja por la pantalla
	_barra_scan = ColorRect.new()
	_barra_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_barra_scan.modulate.a = 0.0
	add_child(_barra_scan)
	_barra_scan.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_barra_scan.offset_bottom = 8.0

	# Barras de cine (arriba y abajo)
	_barra_sup = ColorRect.new()
	_barra_sup.color = Color.BLACK
	_barra_sup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_barra_sup)
	_barra_sup.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_barra_sup.offset_bottom = 0.0

	_barra_inf = ColorRect.new()
	_barra_inf.color = Color.BLACK
	_barra_inf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_barra_inf)
	_barra_inf.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_barra_inf.offset_top = 0.0

	# Cartel con título y narración
	_cartel = MarginContainer.new()
	_cartel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cartel.modulate.a = 0.0
	_cartel.add_theme_constant_override("margin_top", 120)
	_cartel.add_theme_constant_override("margin_left", 180)
	_cartel.add_theme_constant_override("margin_right", 180)

	var columna := VBoxContainer.new()
	columna.add_theme_constant_override("separation", 12)
	columna.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cartel.add_child(columna)

	_label_titulo = Label.new()
	_label_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_titulo.add_theme_font_size_override("font_size", 54)
	_label_titulo.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_label_titulo.add_theme_color_override("font_outline_color", Color.BLACK)
	_label_titulo.add_theme_constant_override("outline_size", 10)
	columna.add_child(_label_titulo)

	_label_texto = Label.new()
	_label_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_texto.add_theme_font_size_override("font_size", 26)
	_label_texto.add_theme_color_override("font_outline_color", Color.BLACK)
	_label_texto.add_theme_constant_override("outline_size", 8)
	columna.add_child(_label_texto)

	add_child(_cartel)
	_cartel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)


# ------------------------------------------------------------
# EJECUTAR EL EVENTO DE UN MES (lo llama el GameManager)
# ------------------------------------------------------------
func ejecutar(mes: int) -> void:
	if not EVENTOS.has(mes):
		return

	var ev: Dictionary = EVENTOS[mes]
	var duracion: float = ev["duracion"]
	var texto: String = ev["texto"]
	if mes == 12:
		texto += "\nHonor acumulado: " + str(HonorManager.puntos_honor)

	_evento_id += 1
	var luz := _luz()
	_energia_normal = luz.light_energy if luz != null else 1.0
	print("🎬 [EVENTO MES ", mes, "]: ", ev["titulo"])

	_mostrar_cartel(ev["titulo"], texto, duracion)
	_barras_cine(true)
	call(ev["efecto"], duracion, _evento_id)

	await get_tree().create_timer(duracion).timeout
	await _terminar_evento()


func _terminar_evento() -> void:
	_evento_id += 1 # detiene los efectos que sigan corriendo

	for nodo in _temporales:
		if is_instance_valid(nodo) and nodo is CPUParticles3D:
			(nodo as CPUParticles3D).emitting = false

	var t := create_tween().set_parallel(true)
	t.tween_property(_cartel, "modulate:a", 0.0, 0.5)
	t.tween_property(_barra_sup, "offset_bottom", 0.0, 0.6)
	t.tween_property(_barra_inf, "offset_top", 0.0, 0.6)
	await t.finished

	_limpiar_temporales()
	_restaurar_luz()
	var cam := _camara()
	if cam != null:
		cam.h_offset = 0.0
		cam.v_offset = 0.0


func _mostrar_cartel(titulo: String, texto: String, dur: float) -> void:
	_label_titulo.text = titulo
	_label_texto.text = texto
	_label_texto.visible_ratio = 0.0
	_cartel.modulate.a = 0.0

	var escribir: float = clampf(texto.length() * 0.03, 1.0, dur - 2.5)
	var t := create_tween()
	t.tween_property(_cartel, "modulate:a", 1.0, 0.5)
	t.parallel().tween_property(_label_texto, "visible_ratio", 1.0, escribir).set_delay(0.5)


func _barras_cine(mostrar: bool) -> void:
	var t := create_tween().set_parallel(true)
	t.tween_property(_barra_sup, "offset_bottom", ALTO_BARRA if mostrar else 0.0, 0.6)
	t.tween_property(_barra_inf, "offset_top", -ALTO_BARRA if mostrar else 0.0, 0.6)


# ------------------------------------------------------------
# AYUDAS
# ------------------------------------------------------------
func _vigente(id: int) -> bool:
	return id == _evento_id


func _luz() -> DirectionalLight3D:
	return get_tree().root.find_child("DirectionalLight3D", true, false) as DirectionalLight3D


func _camara() -> Camera3D:
	var jugador := get_tree().root.find_child("Player", true, false)
	if jugador == null:
		return null
	return jugador.get_node_or_null("Camera3D") as Camera3D


func _padre() -> Node:
	var escena := get_tree().current_scene
	return escena if escena != null else get_tree().root


func _agregar(nodo: Node) -> void:
	_padre().add_child(nodo)
	_temporales.append(nodo)


func _limpiar_temporales() -> void:
	for nodo in _temporales:
		if is_instance_valid(nodo):
			nodo.queue_free()
	_temporales.clear()


func _restaurar_luz() -> void:
	var luz := _luz()
	if luz == null:
		return
	if luz.has_method("actualizar_iluminacion"):
		luz.actualizar_iluminacion()
	else:
		luz.light_energy = _energia_normal


func _destello(color: Color, alfa: float, dur: float) -> void:
	_flash.color = Color(color.r, color.g, color.b, 1.0)
	_flash.modulate.a = alfa
	var t := create_tween()
	t.tween_property(_flash, "modulate:a", 0.0, dur)


func _barrido(color: Color, dur: float) -> void:
	var alto: float = get_viewport().get_visible_rect().size.y
	_barra_scan.color = color
	_barra_scan.modulate.a = 0.9
	_barra_scan.position.y = 0.0
	var t := create_tween()
	t.tween_property(_barra_scan, "position:y", alto, dur)
	t.tween_property(_barra_scan, "modulate:a", 0.0, 0.1)


func _sacudir_camara(intensidad: float, dur: float) -> void:
	var cam := _camara()
	if cam == null:
		return
	var transcurrido: float = 0.0
	while transcurrido < dur:
		var fuerza: float = intensidad * (1.0 - transcurrido / dur)
		cam.h_offset = randf_range(-fuerza, fuerza)
		cam.v_offset = randf_range(-fuerza, fuerza)
		await get_tree().process_frame
		if not is_instance_valid(cam):
			return
		transcurrido += get_process_delta_time()
	cam.h_offset = 0.0
	cam.v_offset = 0.0


func _crear_luz(color: Color, energia: float, rango: float, pos: Vector3) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energia
	l.omni_range = rango
	l.position = pos
	_agregar(l)
	return l


func _crear_particulas(cantidad: int, vida: float, extents: Vector3, tam: Vector3, color: Color, vel_min: float, vel_max: float, grav: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = cantidad
	p.lifetime = vida
	p.preprocess = vida
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3(0, -1, 0)
	p.spread = 4.0
	p.gravity = grav
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.local_coords = false

	var malla := BoxMesh.new()
	malla.size = tam
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	malla.material = mat
	p.mesh = malla
	return p


func _polvo(cantidad: int = 120) -> void:
	var cam := _camara()
	if cam == null:
		return
	var p := _crear_particulas(cantidad, 3.0, Vector3(8, 0.1, 8), Vector3(0.035, 0.035, 0.035), Color(0.85, 0.82, 0.75, 0.55), 0.2, 0.6, Vector3(0, -0.4, 0))
	p.position = cam.global_position + Vector3(0, 3.5, 0)
	_agregar(p)


# ------------------------------------------------------------
# EFECTOS DE CADA MES
# ------------------------------------------------------------
func _ef_bienvenida(_dur: float, id: int) -> void:
	var luz := _luz()
	if luz == null:
		return
	var normal: float = _energia_normal
	luz.light_energy = 0.05
	for i in 7:
		if not _vigente(id):
			return
		luz.light_energy = randf_range(0.05, normal * 0.9)
		await get_tree().create_timer(randf_range(0.07, 0.2)).timeout
	if not _vigente(id):
		return
	var t := create_tween()
	t.tween_property(luz, "light_energy", normal, 0.8)
	_destello(Color(1.0, 0.95, 0.8), 0.25, 0.8)


func _ef_lluvia(_dur: float, id: int) -> void:
	var cam := _camara()
	if cam == null:
		return
	var lluvia := _crear_particulas(450, 0.8, Vector3(10, 0.1, 10), Vector3(0.015, 0.5, 0.015), Color(0.65, 0.78, 1.0, 0.6), 7.0, 10.0, Vector3(0, -20, 0))
	lluvia.position = cam.global_position + Vector3(0, 4.0, 0)
	_agregar(lluvia)

	var luz := _luz()
	if luz != null:
		create_tween().tween_property(luz, "light_energy", _energia_normal * 0.55, 1.0)

	await get_tree().create_timer(1.0).timeout
	if not _vigente(id):
		return
	_destello(Color(0.85, 0.92, 1.0), 0.8, 0.35)
	_sacudir_camara(0.04, 0.6)

	await get_tree().create_timer(2.4).timeout
	if not _vigente(id):
		return
	_destello(Color(0.85, 0.92, 1.0), 0.6, 0.3)
	_sacudir_camara(0.025, 0.4)


func _ef_carga_pesada(_dur: float, id: int) -> void:
	_polvo(120)
	for i in 3:
		if not _vigente(id):
			return
		_sacudir_camara(0.02, 0.8)
		await get_tree().create_timer(1.6).timeout


func _ef_apagon(_dur: float, id: int) -> void:
	var luz := _luz()
	var cam := _camara()
	if luz == null or cam == null:
		return
	luz.light_energy = 1.0
	for i in 8:
		if not _vigente(id):
			return
		luz.light_energy = randf_range(0.0, 1.0)
		await get_tree().create_timer(randf_range(0.05, 0.16)).timeout
	if not _vigente(id):
		return
	luz.light_energy = 0.0
	_sacudir_camara(0.015, 0.4)
	await get_tree().create_timer(0.8).timeout
	if not _vigente(id):
		return

	var roja := _crear_luz(Color(1.0, 0.15, 0.1), 3.5, 16.0, cam.global_position + Vector3(0, 1.5, 0))
	create_tween().tween_property(luz, "light_energy", 0.2, 0.5)
	var t := roja.create_tween().set_loops()
	t.tween_property(roja, "light_energy", 0.3, 0.45)
	t.tween_property(roja, "light_energy", 3.5, 0.45)


func _ef_express(_dur: float, id: int) -> void:
	var cam := _camara()
	if cam == null:
		return
	var sirena := _crear_luz(Color(1.0, 0.2, 0.1), 4.0, 18.0, cam.global_position + Vector3(0, 1.5, 0))
	var t := sirena.create_tween().set_loops()
	t.tween_property(sirena, "light_energy", 0.0, 0.35)
	t.tween_property(sirena, "light_energy", 5.0, 0.35)
	for i in 3:
		if not _vigente(id):
			return
		_destello(Color(1.0, 0.1, 0.05), 0.35, 0.5)
		_sacudir_camara(0.012, 0.5)
		await get_tree().create_timer(1.6).timeout


func _ef_auditoria(_dur: float, id: int) -> void:
	_barrido(Color(0.4, 0.7, 1.0), 1.8)
	for i in 5:
		if not _vigente(id):
			return
		_destello(Color.WHITE, 0.85, 0.18)
		await get_tree().create_timer(randf_range(0.5, 1.1)).timeout


func _ef_mantenimiento(_dur: float, id: int) -> void:
	var cam := _camara()
	if cam == null:
		return
	var frente: Vector3 = -cam.global_transform.basis.z
	frente.y = 0.0
	frente = frente.normalized()
	var punto: Vector3 = cam.global_position + frente * 5.0 + Vector3(0, -0.6, 0)

	var chispas := _crear_particulas(70, 0.7, Vector3(0.1, 0.1, 0.1), Vector3(0.03, 0.03, 0.03), Color(1.0, 0.65, 0.15, 1.0), 2.5, 5.5, Vector3(0, -9.8, 0))
	chispas.direction = Vector3(0, 1, 0)
	chispas.spread = 50.0
	chispas.position = punto
	_agregar(chispas)

	var soldadura := _crear_luz(Color(1.0, 0.6, 0.2), 3.0, 8.0, punto + Vector3(0, 0.4, 0))
	_polvo(90)

	for i in 30:
		if not _vigente(id):
			return
		soldadura.light_energy = randf_range(0.5, 4.0)
		if i % 10 == 0:
			_sacudir_camara(0.01, 0.4)
		await get_tree().create_timer(0.18).timeout


func _ef_temporada(_dur: float, id: int) -> void:
	for i in 4:
		if not _vigente(id):
			return
		_barrido(Color(1.0, 0.7, 0.2), 1.1)
		_destello(Color(1.0, 0.6, 0.1), 0.25, 0.4)
		_sacudir_camara(0.015, 0.5)
		await get_tree().create_timer(1.4).timeout


func _ef_alerta(_dur: float, id: int) -> void:
	var cam := _camara()
	if cam == null:
		return
	_polvo(200)
	var roja := _crear_luz(Color(1.0, 0.1, 0.1), 2.5, 16.0, cam.global_position + Vector3(0, 1.5, 0))
	var t := roja.create_tween().set_loops()
	t.tween_property(roja, "light_energy", 0.2, 0.5)
	t.tween_property(roja, "light_energy", 3.0, 0.5)

	var luz := _luz()
	for i in 4:
		if not _vigente(id):
			return
		if luz != null:
			luz.light_energy = _energia_normal * randf_range(0.6, 1.0)
		_sacudir_camara(0.05, 1.0)
		_destello(Color(1.0, 0.1, 0.05), 0.3, 0.5)
		await get_tree().create_timer(1.4).timeout


func _ef_montacargas(_dur: float, _id: int) -> void:
	# SE ELIMINÓ LA ANIMACIÓN QUE CRUZABA LA PANTALLA.
	# El montacargas real ya se inicializa desde mundo_mes.gd (_preparar_montacargas).
	pass


func _ef_exportacion(_dur: float, id: int) -> void:
	var cam := _camara()
	if cam == null:
		return
	var azul := _crear_luz(Color(0.3, 0.6, 1.0), 2.5, 16.0, cam.global_position + Vector3(0, 1.5, 0))
	var t := azul.create_tween().set_loops()
	t.tween_property(azul, "light_energy", 0.6, 0.6)
	t.tween_property(azul, "light_energy", 3.0, 0.6)
	for i in 3:
		if not _vigente(id):
			return
		_barrido(Color(0.35, 0.7, 1.0), 1.5)
		await get_tree().create_timer(1.9).timeout


func _ef_final(_dur: float, id: int) -> void:
	var cam := _camara()
	if cam == null:
		return
	var dorada := _crear_luz(Color(1.0, 0.8, 0.35), 0.0, 22.0, cam.global_position + Vector3(0, 2.5, 0))
	var t := dorada.create_tween()
	t.tween_property(dorada, "light_energy", 3.0, 1.5)
	t.tween_property(dorada, "light_energy", 1.2, 2.5)
	_destello(Color(1.0, 0.85, 0.45), 0.55, 1.4)

	var luz := _luz()
	if luz != null:
		create_tween().tween_property(luz, "light_energy", _energia_normal * 1.25, 2.0)

	for i in 3:
		await get_tree().create_timer(1.8).timeout
		if not _vigente(id):
			return
		_destello(Color(1.0, 0.85, 0.45), 0.25, 0.7)
