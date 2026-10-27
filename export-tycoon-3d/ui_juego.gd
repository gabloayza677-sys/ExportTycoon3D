extends CanvasLayer
# ============================================================
# ui_juego.gd
# Va en: res://ui_juego.gd  (archivo nuevo, NO va en Globales)
# Lo crea el GameManager. Construye por código:
#  - fundido a negro + mensaje "MES N"
#  - panel de dilema con 2 opciones
#  - contador de Honor
# ============================================================

signal _opcion_elegida(es_etico: bool)

var _fondo: ColorRect
var _label_mes: Label
var _label_honor: Label
var _raiz_dilema: Control
var _label_nombre: Label
var _label_situacion: Label
var _label_ayuda: Label
var _boton_etico: Button
var _boton_atajo: Button

var _esperando_opcion: bool = false
var _modo_mouse_previo: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS # sigue funcionando con el juego en pausa
	_construir_contador_honor()
	_construir_panel_dilema()
	_construir_fondo_negro()
	_conectar_honor()


# ------------------------------------------------------------
# CONSTRUCCIÓN DE LA INTERFAZ
# ------------------------------------------------------------
func _construir_contador_honor() -> void:
	_label_honor = Label.new()
	_label_honor.text = "Honor: 100"
	_label_honor.position = Vector2(24, 18)
	_label_honor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_honor.add_theme_font_size_override("font_size", 26)
	_label_honor.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_label_honor.add_theme_color_override("font_outline_color", Color.BLACK)
	_label_honor.add_theme_constant_override("outline_size", 6)
	add_child(_label_honor)


func _construir_panel_dilema() -> void:
	_raiz_dilema = Control.new()
	_raiz_dilema.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz_dilema.visible = false
	add_child(_raiz_dilema)
	_raiz_dilema.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Columna a pantalla completa con todo pegado ABAJO
	var columna := VBoxContainer.new()
	columna.alignment = BoxContainer.ALIGNMENT_END
	columna.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz_dilema.add_child(columna)
	columna.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margen_externo := MarginContainer.new()
	margen_externo.add_theme_constant_override("margin_left", 140)
	margen_externo.add_theme_constant_override("margin_right", 140)
	margen_externo.add_theme_constant_override("margin_bottom", 40)
	margen_externo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columna.add_child(margen_externo)

	var panel := PanelContainer.new()
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.05, 0.07, 0.12, 0.93)
	estilo.border_color = Color(1.0, 0.85, 0.4, 0.9)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", estilo)
	margen_externo.add_child(panel)

	var margen_interno := MarginContainer.new()
	for lado in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margen_interno.add_theme_constant_override(lado, 24)
	panel.add_child(margen_interno)

	var contenido := VBoxContainer.new()
	contenido.add_theme_constant_override("separation", 12)
	margen_interno.add_child(contenido)

	_label_nombre = Label.new()
	_label_nombre.add_theme_font_size_override("font_size", 28)
	_label_nombre.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	contenido.add_child(_label_nombre)

	_label_situacion = Label.new()
	_label_situacion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label_situacion.custom_minimum_size = Vector2(0, 70)
	_label_situacion.add_theme_font_size_override("font_size", 22)
	contenido.add_child(_label_situacion)

	_boton_etico = _crear_boton(true)
	contenido.add_child(_boton_etico)

	_boton_atajo = _crear_boton(false)
	contenido.add_child(_boton_atajo)

	_label_ayuda = Label.new()
	_label_ayuda.text = "Elige con el mouse o pulsa 1 / 2"
	_label_ayuda.add_theme_font_size_override("font_size", 16)
	_label_ayuda.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	contenido.add_child(_label_ayuda)


func _crear_boton(es_etico: bool) -> Button:
	var boton := Button.new()
	boton.custom_minimum_size = Vector2(0, 52)
	boton.alignment = HORIZONTAL_ALIGNMENT_LEFT
	boton.add_theme_font_size_override("font_size", 20)
	boton.pressed.connect(_elegir.bind(es_etico))
	return boton


func _construir_fondo_negro() -> void:
	_fondo = ColorRect.new()
	_fondo.color = Color.BLACK
	_fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fondo.modulate.a = 0.0
	add_child(_fondo)
	_fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_label_mes = Label.new()
	_label_mes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_mes.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_mes.add_theme_font_size_override("font_size", 96)
	_label_mes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_mes.modulate.a = 0.0
	add_child(_label_mes)
	_label_mes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# ------------------------------------------------------------
# HONOR
# ------------------------------------------------------------
func _conectar_honor() -> void:
	await get_tree().process_frame # esperamos a que todos los Autoloads existan
	_actualizar_honor(HonorManager.puntos_honor)
	if not HonorManager.honor_cambiado.is_connected(_on_honor_cambiado):
		HonorManager.honor_cambiado.connect(_on_honor_cambiado)


func _on_honor_cambiado(puntos: int, _cambio: int) -> void:
	_actualizar_honor(puntos)


func _actualizar_honor(puntos: int) -> void:
	_label_honor.text = "Honor: " + str(puntos)


# ------------------------------------------------------------
# FUNDIDO A NEGRO + MENSAJE DE MES
# ------------------------------------------------------------
func poner_negro(mes: int) -> void:
	# Pantalla negra INSTANTÁNEA con el mensaje (para el inicio del juego)
	_fondo.modulate.a = 1.0
	_label_mes.text = "MES " + str(mes)
	_label_mes.modulate.a = 1.0


func fundido_a_negro(mes: int, duracion: float = 0.9) -> void:
	_label_mes.text = "MES " + str(mes)
	var t := create_tween()
	t.tween_property(_fondo, "modulate:a", 1.0, duracion)
	t.tween_property(_label_mes, "modulate:a", 1.0, 0.4)
	await t.finished


func cambiar_mes_en_pantalla(mes: int) -> void:
	# "MES 1" se desvanece y aparece "MES 2"
	var t := create_tween()
	t.tween_property(_label_mes, "modulate:a", 0.0, 0.25)
	t.tween_callback(func() -> void: _label_mes.text = "MES " + str(mes))
	t.tween_property(_label_mes, "modulate:a", 1.0, 0.25)
	await t.finished


func aclarar(duracion: float = 0.9) -> void:
	var t := create_tween()
	t.tween_property(_label_mes, "modulate:a", 0.0, 0.3)
	t.tween_property(_fondo, "modulate:a", 0.0, duracion)
	await t.finished


func mantener_y_aclarar(espera: float) -> void:
	await get_tree().create_timer(espera).timeout
	await aclarar()


# ------------------------------------------------------------
# PANEL DE DILEMA
# ------------------------------------------------------------
func mostrar_dilema(nombre: String, rol: String, situacion: String, texto_etico: String, texto_atajo: String) -> bool:
	get_tree().paused = true
	_modo_mouse_previo = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_label_nombre.text = nombre + "  -  " + rol
	_label_situacion.text = situacion
	_boton_etico.text = texto_etico
	_boton_atajo.text = texto_atajo
	_boton_etico.visible = true
	_boton_atajo.visible = true
	_label_ayuda.visible = true
	_raiz_dilema.visible = true

	_esperando_opcion = true
	var es_etico: bool = await _opcion_elegida
	return es_etico


func cerrar_dilema(es_etico: bool, puntos: int) -> void:
	_boton_etico.visible = false
	_boton_atajo.visible = false
	_label_ayuda.visible = false

	var signo: String = "+" if puntos > 0 else ""
	if es_etico:
		_label_situacion.text = "Decisión ética.   " + signo + str(puntos) + " de Honor"
	else:
		_label_situacion.text = "Tomaste el atajo.   " + signo + str(puntos) + " de Honor"

	await get_tree().create_timer(2.0).timeout

	_raiz_dilema.visible = false
	get_tree().paused = false
	Input.mouse_mode = _modo_mouse_previo


func _elegir(es_etico: bool) -> void:
	if not _esperando_opcion:
		return
	_esperando_opcion = false
	_opcion_elegida.emit(es_etico)


func _unhandled_input(event: InputEvent) -> void:
	if not _esperando_opcion:
		return
	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo:
		return
	if tecla.keycode == KEY_1 or tecla.keycode == KEY_KP_1:
		get_viewport().set_input_as_handled()
		_elegir(true)
	elif tecla.keycode == KEY_2 or tecla.keycode == KEY_KP_2:
		get_viewport().set_input_as_handled()
		_elegir(false)
