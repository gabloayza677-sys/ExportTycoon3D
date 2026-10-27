extends CanvasLayer
# ============================================================
# hud_estado.gd   ->  res://hud_estado.gd   (lo crea el GameManager)
# Interfaz minimalista y tipografía moderna (fuente del sistema:
# Inter / Segoe UI / Helvetica...). SIN barra de honor.
# Muestra: mes, cajas, stamina, cuenta regresiva, pistas, avisos
# y la pantalla de evaluación final.
# ============================================================

const ANCHO_BARRA: float = 240.0
const FUENTES: Array = ["Inter", "Segoe UI Variable", "Segoe UI", "SF Pro Display", "Helvetica Neue", "Arial"]

var _raiz: Control
var _lbl_mes: Label
var _lbl_cajas: Label
var _cont_stamina: Control
var _fill: ColorRect
var _lbl_pista: Label
var _lbl_frase: Label
var _lbl_aviso: Label
var _lbl_cuenta: Label
var _lbl_cuenta_sub: Label
var _lbl_toast: Label
var _flash: ColorRect
var _tw_frase: Tween
var _tw_toast: Tween


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS

	_raiz = Control.new()
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_raiz)
	_raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Mes y cajas (arriba a la izquierda)
	_lbl_mes = _etiqueta(15, 600, HORIZONTAL_ALIGNMENT_LEFT, Color(1, 1, 1, 0.85))
	_raiz.add_child(_lbl_mes)
	_lbl_mes.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_lbl_mes.offset_left = 28; _lbl_mes.offset_top = 22; _lbl_mes.offset_right = 300; _lbl_mes.offset_bottom = 44

	_lbl_cajas = _etiqueta(13, 300, HORIZONTAL_ALIGNMENT_LEFT, Color(1, 1, 1, 0.6))
	_raiz.add_child(_lbl_cajas)
	_lbl_cajas.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_lbl_cajas.offset_left = 28; _lbl_cajas.offset_top = 44; _lbl_cajas.offset_right = 300; _lbl_cajas.offset_bottom = 64

	# Stamina (fina, abajo al centro; se oculta cuando está llena)
	_cont_stamina = Control.new()
	_cont_stamina.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cont_stamina.modulate.a = 0.0
	_raiz.add_child(_cont_stamina)
	_cont_stamina.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_cont_stamina.offset_left = -ANCHO_BARRA * 0.5; _cont_stamina.offset_right = ANCHO_BARRA * 0.5
	_cont_stamina.offset_top = -54; _cont_stamina.offset_bottom = -51
	var fondo := ColorRect.new()
	fondo.color = Color(1, 1, 1, 0.14)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cont_stamina.add_child(fondo)
	fondo.size = Vector2(ANCHO_BARRA, 3)
	_fill = ColorRect.new()
	_fill.color = Color(1, 1, 1, 0.85)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cont_stamina.add_child(_fill)
	_fill.size = Vector2(ANCHO_BARRA, 3)

	# Pista contextual (sobre la stamina)
	_lbl_pista = _etiqueta(14, 400, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1, 0.75))
	_raiz.add_child(_lbl_pista)
	_lbl_pista.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_lbl_pista.offset_left = -480; _lbl_pista.offset_right = 480; _lbl_pista.offset_top = -92; _lbl_pista.offset_bottom = -66

	# Frase central (premisa, mensajes)
	_lbl_frase = _etiqueta(26, 200, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1, 0.95))
	_lbl_frase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_frase.modulate.a = 0.0
	_raiz.add_child(_lbl_frase)
	_lbl_frase.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_lbl_frase.offset_left = -520; _lbl_frase.offset_right = 520; _lbl_frase.offset_top = 150; _lbl_frase.offset_bottom = 210

	# Aviso permanente (mes 11)
	_lbl_aviso = _etiqueta(14, 500, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.78, 0.45, 0.85))
	_lbl_aviso.visible = false
	_raiz.add_child(_lbl_aviso)
	_lbl_aviso.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_lbl_aviso.offset_left = -320; _lbl_aviso.offset_right = 320; _lbl_aviso.offset_top = 24; _lbl_aviso.offset_bottom = 48

	# Cuenta regresiva (mes 5)
	_lbl_cuenta = _etiqueta(48, 200, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1, 0.95))
	_lbl_cuenta.visible = false
	_raiz.add_child(_lbl_cuenta)
	_lbl_cuenta.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_lbl_cuenta.offset_left = -160; _lbl_cuenta.offset_right = 160; _lbl_cuenta.offset_top = 40; _lbl_cuenta.offset_bottom = 104
	_lbl_cuenta_sub = _etiqueta(12, 500, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1, 0.55))
	_lbl_cuenta_sub.visible = false
	_raiz.add_child(_lbl_cuenta_sub)
	_lbl_cuenta_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_lbl_cuenta_sub.offset_left = -220; _lbl_cuenta_sub.offset_right = 220; _lbl_cuenta_sub.offset_top = 102; _lbl_cuenta_sub.offset_bottom = 122

	# Toast de consecuencias (abajo a la derecha)
	_lbl_toast = _etiqueta(14, 400, HORIZONTAL_ALIGNMENT_RIGHT, Color(1, 1, 1, 0.8))
	_lbl_toast.modulate.a = 0.0
	_raiz.add_child(_lbl_toast)
	_lbl_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_lbl_toast.offset_left = -460; _lbl_toast.offset_right = -28; _lbl_toast.offset_top = -96; _lbl_toast.offset_bottom = -66

	# Destello (cámaras de los auditores)
	_flash = ColorRect.new()
	_flash.color = Color.WHITE
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	_raiz.add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	HonorManager.consecuencia.connect(_on_consecuencia)


func _fuente(peso: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(FUENTES)
	f.font_weight = peso
	return f


func _etiqueta(tam: int, peso: int, alinea: HorizontalAlignment, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _fuente(peso))
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.horizontal_alignment = alinea
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	_lbl_cajas.text = "%d / %d cajas" % [GameManager.cajas_procesadas_mes, GameManager.cajas_meta_mes]

	var j = get_tree().get_first_node_in_group("jugador")
	if j == null:
		return
	var r: float = clampf(j.stamina / j.STAMINA_MAX, 0.0, 1.0)
	_fill.size.x = ANCHO_BARRA * r
	var cansado: bool = j.agotado or r < 0.25
	_fill.color = Color(1.0, 0.62, 0.25, 0.95) if cansado else Color(1, 1, 1, 0.85)
	var objetivo: float = 0.0 if r >= 0.999 else 0.9
	_cont_stamina.modulate.a = move_toward(_cont_stamina.modulate.a, objetivo, delta * 2.0)


# ------------------------------------------------------------
# API PÚBLICA
# ------------------------------------------------------------
func set_mes(m: int) -> void:
	_lbl_mes.text = "MES %02d" % m


func set_pista(texto: String) -> void:
	_lbl_pista.text = texto


func mensaje(texto: String, dur: float = 3.5) -> void:
	if _tw_frase != null and _tw_frase.is_valid():
		_tw_frase.kill()
	_lbl_frase.text = texto
	_tw_frase = create_tween()
	_tw_frase.tween_property(_lbl_frase, "modulate:a", 1.0, 0.7)
	_tw_frase.tween_interval(dur)
	_tw_frase.tween_property(_lbl_frase, "modulate:a", 0.0, 0.9)


func aviso_permanente(texto: String) -> void:
	_lbl_aviso.text = texto
	_lbl_aviso.visible = texto != ""


func mostrar_cuenta(sub: String) -> void:
	_lbl_cuenta.visible = true
	_lbl_cuenta_sub.visible = true
	_lbl_cuenta_sub.text = sub.to_upper()


func actualizar_cuenta(segundos: float) -> void:
	var s: int = maxi(0, int(ceil(segundos)))
	_lbl_cuenta.text = "%d:%02d" % [s / 60, s % 60]
	if segundos < 30.0:
		var pulso: float = 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.012)
		_lbl_cuenta.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25, pulso))
	else:
		_lbl_cuenta.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))


func ocultar_cuenta() -> void:
	_lbl_cuenta.visible = false
	_lbl_cuenta_sub.visible = false


func destello(alfa: float = 0.5) -> void:
	_flash.modulate.a = alfa
	create_tween().tween_property(_flash, "modulate:a", 0.0, 0.25)


func _on_consecuencia(texto: String, _cambio: int) -> void:
	# Nunca mostramos números: solo que "algo quedó registrado"
	if _tw_toast != null and _tw_toast.is_valid():
		_tw_toast.kill()
	_lbl_toast.text = texto
	_tw_toast = create_tween()
	_tw_toast.tween_property(_lbl_toast, "modulate:a", 1.0, 0.3)
	_tw_toast.tween_interval(2.8)
	_tw_toast.tween_property(_lbl_toast, "modulate:a", 0.0, 0.8)


# ------------------------------------------------------------
# EVALUACIÓN FINAL (mes 12)
# ------------------------------------------------------------
func mostrar_evaluacion(d: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bueno: bool = d["resultado"] == "bueno"

	var fondo := ColorRect.new()
	fondo.color = Color(0, 0, 0, 0.0)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.add_child(fondo)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t := create_tween()
	t.tween_property(fondo, "color:a", 0.86, 1.2)
	await t.finished

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.modulate.a = 0.0
	fondo.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.offset_left = -300; col.offset_right = 300; col.offset_top = -230; col.offset_bottom = 230

	var cab := _etiqueta(13, 600, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1, 0.5))
	cab.text = "EVALUACIÓN FINAL"
	col.add_child(cab)

	var titulo := _etiqueta(46, 200, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.95, 0.65) if bueno else Color(1.0, 0.42, 0.38))
	titulo.text = "FINAL BUENO" if bueno else "FINAL MALO"
	col.add_child(titulo)

	var cita := _etiqueta(18, 300, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 1, 1, 0.85))
	cita.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if bueno:
		cita.text = "«Orden, rapidez y criterio. Cada decisión tuya dejó huella, y fue la correcta. El puesto de encargado es tuyo.»"
	else:
		cita.text = "«Las cajas salieron, sí. Pero cada atajo y cada descuido tuvo consecuencias. Recoge tus cosas.»"
	col.add_child(cita)

	var rejilla := GridContainer.new()
	rejilla.columns = 2
	rejilla.add_theme_constant_override("h_separation", 40)
	rejilla.add_theme_constant_override("v_separation", 6)
	col.add_child(rejilla)
	_fila(rejilla, "Consecuencias", "%d %%" % int(round(d["consecuencias"] * 100.0)))
	_fila(rejilla, "Eficiencia con las cajas", "%d %%" % int(round(d["eficiencia_cajas"] * 100.0)))
	if d["palets_generados"] > 0:
		_fila(rejilla, "Palets ordenados", "%d / %d" % [d["palets_ordenados"], d["palets_generados"]])
	_fila(rejilla, "Nota global", "%d %%" % int(round(d["nota"] * 100.0)))

	var boton := Button.new()
	boton.text = "Salir"
	boton.add_theme_font_override("font", _fuente(400))
	boton.custom_minimum_size = Vector2(160, 40)
	boton.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	boton.pressed.connect(func() -> void: get_tree().quit())
	col.add_child(boton)

	create_tween().tween_property(col, "modulate:a", 1.0, 1.0)


func _fila(rejilla: GridContainer, nombre: String, valor: String) -> void:
	var a := _etiqueta(16, 300, HORIZONTAL_ALIGNMENT_LEFT, Color(1, 1, 1, 0.65))
	a.text = nombre
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := _etiqueta(16, 600, HORIZONTAL_ALIGNMENT_RIGHT, Color(1, 1, 1, 0.95))
	b.text = valor
	rejilla.add_child(a)
	rejilla.add_child(b)
