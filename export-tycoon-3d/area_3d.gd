extends Area3D
# ============================================================
# area_3d.gd
# Va en: el Area3D de cada camión donde se entregan cajas.
# El CollisionShape3D (BoxShape3D) hijo de este Area3D marca el
# ESPACIO DE CARGA del camión: las cajas se acomodan solas dentro.
# ============================================================

@export_category("Entrega")
## true = la caja se entrega sola al acercarte. false = hay que pulsar E.
@export var entrega_automatica: bool = true
## Metros extra alrededor del espacio de carga desde donde puedes entregar.
@export var margen_zona: float = 2.0
## Distancia máxima al centro de la zona (para detectar entregas hechas por otro script).
@export var distancia_maxima: float = 8.0

@export_category("Ciclo del camión (sale al llenarse y vuelve vacío)")
## Si está desactivado, al llenarse el camión se vacía al instante (comportamiento antiguo).
@export var animar_salida: bool = true
## Nodo del camión que se mueve. Vacío = el padre de este Area3D (si no es la escena raíz).
@export var nodo_camion: NodePath = NodePath("")
@export var duracion_salida: float = 6.0
@export var espera_fuera: float = 5.0
@export var duracion_regreso: float = 5.0
## Distancia que recorre por la autopista antes de salir de pantalla.
@export var distancia_via: float = 140.0
## 1 o -1: hacia qué lado de la autopista gira al salir (cámbialo si sale por el lado contrario).
@export var sentido_giro: float = 1.0

@export_category("Solo si NO hay un CollisionShape3D con BoxShape3D (modo manual)")
@export var origen_carga: Vector3 = Vector3.ZERO
@export var columnas: int = 2
@export var filas: int = 4
@export var capas: int = 3
@export var separacion: Vector3 = Vector3(1.0, 0.9, 1.3)

const TAM_CAJA: Vector3 = Vector3(0.9, 0.85, 1.2)
const HUECO: float = 0.04
const MAX_SLOTS: int = 150

var _jugador: CharacterBody3D = null
var _cajas_en_camion: Array[Node3D] = []
var _slots: Array[Transform3D] = []
var _sentido_largo: int = 1
var _mes_visto: int = 1
var _mano_tenia_caja: bool = false

# --- ciclo del camión ---
enum Fase { PARADO, SALIENDO, AUSENTE, ACERCANDO, REVERSA }
var _fase: Fase = Fase.PARADO
var _t_fase: float = 0.0
var _camion: Node3D = null
var _carga: Node3D = null              # raíz de las cajas cargadas (se mueve con el camión)
var _pos_base: Transform3D = Transform3D.IDENTITY
var _ruta: PackedVector3Array = PackedVector3Array()
var _acum: PackedFloat32Array = PackedFloat32Array()
var _s_giro: float = 0.0               # distancia recorrida al terminar la curva
var _eje_base: Vector3 = Vector3(0, 0, 1)
var _q0: Vector3 = Vector3.ZERO
var _q1: Vector3 = Vector3.ZERO
var _yaw_via: float = 0.0
var _fuera: bool = false
var _t_aviso: float = 0.0


func _ready() -> void:
	# Sigue funcionando con el juego en pausa (para vaciar el camión con la pantalla negra)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("zonas_entrega")
	_mes_visto = GameManager.mes_actual
	_iniciar.call_deferred()


func _iniciar() -> void:
	_resolver_camion()
	_slots = _calcular_slots()
	print("🚚 Zona de entrega lista: ", name, " | capacidad: ", _slots.size())


func _process(_delta: float) -> void:
	# Cuando cambia el mes, el camión se va vacío (ocurre con la pantalla negra)
	_animar_camion(_delta)

	if GameManager.mes_actual != _mes_visto:
		_mes_visto = GameManager.mes_actual
		_reiniciar_camion()

	var camara := _obtener_camara()
	if camara == null:
		return

	var caja_mano = camara.get_node_or_null("CajaEnMano")
	var tiene_caja: bool = caja_mano != null and caja_mano.visible
	var perdio_caja: bool = _mano_tenia_caja and not tiene_caja
	_mano_tenia_caja = tiene_caja

	if get_tree().paused or GameManager.en_transicion:
		return

	var pj: Vector3 = _jugador.global_position
	var pc: Vector3 = camara.global_position

	if tiene_caja and entrega_automatica:
		# Entrega normal: llevas caja y estás junto al camión más cercano
		if _soy_la_zona_activa(pj, pc, false):
			_entregar_caja(caja_mano)
		elif _fuera and pj.distance_to(_pos_base.origin) < 12.0:
			var ahora: float = Time.get_ticks_msec() / 1000.0
			if ahora - _t_aviso > 4.0 and GameManager.hud != null:
				_t_aviso = ahora
				GameManager.hud.mensaje("El camión está en reparto. Espera a que regrese vacío.", 2.5)
	elif perdio_caja:
		# Otro script (el viejo) te quitó la caja de las manos: lo registramos igual
		if _soy_la_zona_activa(pj, pc, true):
			_registrar_entrega()


func _unhandled_input(event: InputEvent) -> void:
	# Solo se usa si entrega_automatica = false
	if entrega_automatica or get_tree().paused or GameManager.en_transicion:
		return

	var tecla := event as InputEventKey
	if tecla == null or not tecla.pressed or tecla.echo or tecla.keycode != KEY_E:
		return

	var camara := _obtener_camara()
	if camara == null:
		return

	var caja_mano = camara.get_node_or_null("CajaEnMano")
	if caja_mano == null or not caja_mano.visible:
		return
	if not _soy_la_zona_activa(_jugador.global_position, camara.global_position, false):
		return

	get_viewport().set_input_as_handled()
	_entregar_caja(caja_mano)


# ------------------------------------------------------------
# VARIOS CAMIONES: SOLO ACTÚA EL MÁS CERCANO
# ------------------------------------------------------------
func _soy_la_zona_activa(pj: Vector3, pc: Vector3, ampliado: bool) -> bool:
	var mejor: Node = null
	var mejor_dist: float = INF
	for zona in get_tree().get_nodes_in_group("zonas_entrega"):
		var d: float = zona.distancia_de_entrega(pj, pc, ampliado)
		if d < mejor_dist:
			mejor_dist = d
			mejor = zona
	return mejor == self


## Devuelve la distancia del jugador a esta zona, o INF si no está lo bastante cerca.
func distancia_de_entrega(pj: Vector3, pc: Vector3, ampliado: bool) -> float:
	if _fuera:
		return INF      # el camión está en la autopista: no recibe cajas
	var d: float = centro_de_zona().distance_to(pj)
	if ampliado:
		return d if d <= distancia_maxima else INF
	return d if (_punto_en_zona(pj) or _punto_en_zona(pc)) else INF


func centro_de_zona() -> Vector3:
	var col := _buscar_forma_caja()
	return col.global_position if col != null else global_position


# ------------------------------------------------------------
# ENTREGA
# ------------------------------------------------------------
func _entregar_caja(caja_mano: Node) -> void:
	caja_mano.visible = false
	_mano_tenia_caja = false
	_registrar_entrega()


func _registrar_entrega() -> void:
	# Otro script entregó mientras el camión estaba fuera: cuenta igual, solo no se ve
	if _fuera:
		GameManager.registrar_caja_colocada()
		return

	# Sin animación (o sin nodo de camión): al llenarse, sale a reparto y llega uno vacío
	if not _slots.is_empty() and _cajas_en_camion.size() >= _slots.size():
		print("🚚 Camión lleno: sale a reparto y llega uno vacío.")
		_vaciar_camion()

	# Al empezar a cargar, se decide por qué extremo se empieza a llenar
	if _cajas_en_camion.is_empty():
		_actualizar_sentido()
		_slots = _calcular_slots()

	_colocar_caja_visible(_cajas_en_camion.size())
	print("🚚 ¡Caja entregada en el camión! (", _cajas_en_camion.size(), " / ", _slots.size(), ")")

	# Aquí se cuenta para el mes (si era la última, empieza el mes siguiente)
	GameManager.registrar_caja_colocada()

	# Camión lleno -> sale por el hueco, circula por la autopista y regresa vacío
	if animar_salida and not _slots.is_empty() and _cajas_en_camion.size() >= _slots.size() \
			and _fase == Fase.PARADO and not GameManager.en_transicion:
		_iniciar_salida()


func _colocar_caja_visible(indice: int) -> void:
	if indice >= _slots.size():
		return

	var caja := MeshInstance3D.new()
	var malla := BoxMesh.new()
	malla.size = TAM_CAJA
	caja.mesh = malla

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.48, 0.28) # Color cartón
	caja.material_override = material

	_padre_carga().add_child(caja)
	caja.global_transform = _slots[indice]
	_cajas_en_camion.append(caja)


func _vaciar_camion() -> void:
	for caja in _cajas_en_camion:
		if is_instance_valid(caja):
			caja.queue_free()
	_cajas_en_camion.clear()


# ------------------------------------------------------------
# ¿ESTÁ EL JUGADOR EN LA ZONA?
# ------------------------------------------------------------
func _obtener_camara() -> Camera3D:
	if not is_instance_valid(_jugador):
		_jugador = get_tree().root.find_child("Player", true, false) as CharacterBody3D
	if _jugador == null:
		return null
	return _jugador.get_node_or_null("Camera3D") as Camera3D


func _buscar_forma_caja() -> CollisionShape3D:
	for hijo in get_children():
		var col := hijo as CollisionShape3D
		if col != null and col.shape is BoxShape3D:
			return col
	return null


func _punto_en_zona(p: Vector3) -> bool:
	var col := _buscar_forma_caja()
	if col == null:
		return global_position.distance_to(p) <= distancia_maxima

	var forma := col.shape as BoxShape3D
	var escala: Vector3 = col.global_transform.basis.get_scale().abs()
	var margen := Vector3(
		margen_zona / maxf(escala.x, 0.001),
		margen_zona / maxf(escala.y, 0.001),
		margen_zona / maxf(escala.z, 0.001))
	var mitad: Vector3 = forma.size * 0.5 + margen
	var local: Vector3 = col.global_transform.affine_inverse() * p
	return absf(local.x) <= mitad.x and absf(local.y) <= mitad.y and absf(local.z) <= mitad.z


# ------------------------------------------------------------
# DÓNDE VA CADA CAJA (se acomodan solas dentro del espacio de carga)
# ------------------------------------------------------------
func _actualizar_sentido() -> void:
	# Se empieza a llenar por el extremo más lejano a ti (el fondo del camión)
	var col := _buscar_forma_caja()
	if col == null or not is_instance_valid(_jugador):
		return
	var t: Transform3D = col.global_transform
	var tam: Vector3 = (col.shape as BoxShape3D).size * t.basis.get_scale().abs()
	var base: Basis = t.basis.orthonormalized()
	var eje_largo: Vector3 = base.x if tam.x >= tam.z else base.z
	_sentido_largo = -1 if (t.origin - _jugador.global_position).dot(eje_largo) > 0.0 else 1


func _calcular_slots() -> Array[Transform3D]:
	var col := _buscar_forma_caja()
	if col == null:
		return _calcular_slots_manual()

	var forma := col.shape as BoxShape3D
	var t: Transform3D = col.global_transform
	var tam: Vector3 = forma.size * t.basis.get_scale().abs() # tamaño real en metros
	var base: Basis = t.basis.orthonormalized()
	var centro: Vector3 = t.origin

	# Dos formas de acomodar las cajas (giradas o no): elegimos la que más cabe
	var a_x: int = maxi(floori(tam.x / (TAM_CAJA.x + HUECO)), 1)
	var a_z: int = maxi(floori(tam.z / (TAM_CAJA.z + HUECO)), 1)
	var b_x: int = maxi(floori(tam.x / (TAM_CAJA.z + HUECO)), 1)
	var b_z: int = maxi(floori(tam.z / (TAM_CAJA.x + HUECO)), 1)
	var sin_girar: bool = a_x * a_z >= b_x * b_z

	var nx: int = a_x if sin_girar else b_x
	var nz: int = a_z if sin_girar else b_z
	var paso_x: float = (TAM_CAJA.x if sin_girar else TAM_CAJA.z) + HUECO
	var paso_z: float = (TAM_CAJA.z if sin_girar else TAM_CAJA.x) + HUECO
	var paso_y: float = TAM_CAJA.y + HUECO
	var n_capas: int = maxi(floori(tam.y / paso_y), 1)
	var base_cajas: Basis = base if sin_girar else base * Basis(Vector3.UP, PI * 0.5)

	var largo_en_x: bool = tam.x >= tam.z
	var n_largo: int = nx if largo_en_x else nz
	var n_ancho: int = nz if largo_en_x else nx

	var slots: Array[Transform3D] = []
	for k in n_capas:
		for il in n_largo:
			var pos_l: int = il if _sentido_largo > 0 else (n_largo - 1 - il)
			for iw in n_ancho:
				if slots.size() >= MAX_SLOTS:
					push_warning("La zona de carga de '%s' es enorme: se limitó a %d cajas. Haz más pequeño su CollisionShape3D." % [name, MAX_SLOTS])
					return slots

				var ix: int = pos_l if largo_en_x else iw
				var iz: int = iw if largo_en_x else pos_l
				var local := Vector3(
					(ix - (nx - 1) / 2.0) * paso_x,
					-tam.y * 0.5 + k * paso_y + TAM_CAJA.y * 0.5, # apoyadas en el fondo
					(iz - (nz - 1) / 2.0) * paso_z)
				slots.append(Transform3D(base_cajas, centro + base * local))
	return slots


func _calcular_slots_manual() -> Array[Transform3D]:
	var slots: Array[Transform3D] = []
	var cols: int = maxi(columnas, 1)
	var fils: int = maxi(filas, 1)
	var base: Basis = global_transform.basis.orthonormalized()

	for capa in maxi(capas, 1):
		for fila in fils:
			for col in cols:
				var local: Vector3 = origen_carga + Vector3(
					(col - (cols - 1) / 2.0) * separacion.x,
					capa * separacion.y + TAM_CAJA.y * 0.5,
					(fila - (fils - 1) / 2.0) * separacion.z)
				slots.append(Transform3D(base, global_transform.origin + base * local))
	return slots


func _padre_carga() -> Node:
	if _carga == null or not is_instance_valid(_carga):
		_carga = Node3D.new()
		_carga.name = "Carga_" + String(name)
		var escena := get_tree().current_scene
		(escena if escena != null else get_tree().root).add_child(_carga)
	return _carga

# ------------------------------------------------------------
# CICLO DEL CAMIÓN: sale por el hueco -> autopista -> fuera de pantalla -> vuelve vacío
# ------------------------------------------------------------
func capacidad() -> int:
	return _slots.size()


func _resolver_camion() -> void:
	_camion = null
	if nodo_camion != NodePath(""):
		_camion = get_node_or_null(nodo_camion) as Node3D
	if _camion == null:
		var p := get_parent() as Node3D
		if p != null and p != get_tree().current_scene and p != get_tree().root:
			_camion = p
	if _camion != null:
		_pos_base = _camion.global_transform
	elif animar_salida:
		push_warning("'%s': no encontré el nodo del camión; se usará el vaciado instantáneo." % name)


func _iniciar_salida() -> void:
	if _camion == null or not _preparar_ruta():
		return
	_fuera = true
	_fase = Fase.SALIENDO
	_t_fase = -0.7          # pequeña pausa antes de arrancar
	print("🚚 ", name, " sale a reparto.")


func _preparar_ruta() -> bool:
	var base: Vector3 = _pos_base.origin
	var n := Vector3(0, 0, 1)
	var d_carril: float = 15.0
	var mundo = GameManager.mundo
	if mundo != null and mundo.has_method("hueco_mas_cercano"):
		var h: Dictionary = mundo.hueco_mas_cercano(base)
		if not h.is_empty():
			n = h["normal"]
			d_carril = mundo.distancia_carril() - (base - h["pos"]).dot(n)
	n.y = 0.0
	if n.length() < 0.01:
		return false
	n = n.normalized()
	_eje_base = n
	var tau: Vector3 = Vector3.UP.cross(n) * signf(sentido_giro)
	var radio: float = 5.0
	var d1: float = maxf(d_carril, radio + 3.0)
	var p1: Vector3 = base + n * d1
	var p1b: Vector3 = p1 - n * radio
	var p1c: Vector3 = p1 + tau * radio

	var pts := PackedVector3Array()
	pts.append(base)
	pts.append(p1b)
	for i in range(1, 9):                       # curva (Bézier cuadrática)
		var u: float = float(i) / 8.0
		pts.append(p1b.lerp(p1, u).lerp(p1.lerp(p1c, u), u))
	pts.append(p1c + tau * distancia_via)

	_acum = PackedFloat32Array()
	_acum.append(0.0)
	for i in range(1, pts.size()):
		_acum.append(_acum[i - 1] + pts[i - 1].distance_to(pts[i]))
	_ruta = pts
	_s_giro = _acum[pts.size() - 2]             # justo al terminar la curva
	_yaw_via = _yaw_de(tau)
	_q0 = p1c - tau * distancia_via             # llega por el otro lado de la autopista
	_q1 = p1c
	return true


func _yaw_de(dir: Vector3) -> float:
	return atan2(_eje_base.cross(dir).dot(Vector3.UP), _eje_base.dot(dir))


func _pose_en_ruta(s: float) -> void:
	s = clampf(s, 0.0, _acum[_acum.size() - 1])
	var i: int = 1
	while i < _acum.size() - 1 and _acum[i] < s:
		i += 1
	var a: Vector3 = _ruta[i - 1]
	var b: Vector3 = _ruta[i]
	var largo: float = maxf(_acum[i] - _acum[i - 1], 0.001)
	var pos: Vector3 = a.lerp(b, clampf((s - _acum[i - 1]) / largo, 0.0, 1.0))
	var dir: Vector3 = (b - a)
	dir.y = 0.0
	_poner_pose(pos, _yaw_de(dir.normalized()) if dir.length() > 0.001 else 0.0)


func _poner_pose(pos: Vector3, yaw: float) -> void:
	if _camion == null:
		return
	var t := Transform3D(Basis(Vector3.UP, yaw) * _pos_base.basis, Vector3(pos.x, _pos_base.origin.y, pos.z))
	_camion.global_transform = t
	if _carga != null and is_instance_valid(_carga):
		_carga.global_transform = t * _pos_base.affine_inverse()


func _mostrar_camion(visible_: bool) -> void:
	if _camion != null:
		_camion.visible = visible_
	if _carga != null and is_instance_valid(_carga):
		_carga.visible = visible_


func _animar_camion(delta: float) -> void:
	if _fase == Fase.PARADO or _camion == null:
		return
	_t_fase += delta
	match _fase:
		Fase.SALIENDO:
			var u: float = clampf(_t_fase / duracion_salida, 0.0, 1.0)
			_pose_en_ruta(_acum[_acum.size() - 1] * u * u)       # arranca despacio y acelera
			if u >= 1.0:
				_mostrar_camion(false)
				_vaciar_camion()                                 # la caja de atrás queda vacía
				_fase = Fase.AUSENTE
				_t_fase = 0.0
		Fase.AUSENTE:
			if _t_fase >= espera_fuera:
				_poner_pose(_q0, _yaw_via)
				_mostrar_camion(true)
				_fase = Fase.ACERCANDO
				_t_fase = 0.0
		Fase.ACERCANDO:
			var u: float = clampf(_t_fase / duracion_regreso, 0.0, 1.0)
			var v: float = 1.0 - (1.0 - u) * (1.0 - u)           # frena al llegar
			_poner_pose(_q0.lerp(_q1, v), _yaw_via)
			if u >= 1.0:
				_fase = Fase.REVERSA
				_t_fase = 0.0
		Fase.REVERSA:
			var u: float = clampf(_t_fase / (duracion_regreso * 0.7), 0.0, 1.0)
			var v: float = u * u * (3.0 - 2.0 * u)
			_pose_en_ruta(_s_giro * (1.0 - v))                   # marcha atrás hasta el muelle
			if u >= 1.0:
				_terminar_ciclo()


func _terminar_ciclo() -> void:
	_fase = Fase.PARADO
	_fuera = false
	if _camion != null:
		_camion.global_transform = _pos_base
	if _carga != null and is_instance_valid(_carga):
		_carga.global_transform = Transform3D.IDENTITY
	_mostrar_camion(true)
	_slots = _calcular_slots()
	print("🚚 ", name, " volvió vacío al muelle.")


## Cambio de mes (pantalla negra): el camión vuelve al muelle ya vacío.
func _reiniciar_camion() -> void:
	_vaciar_camion()
	if _fase != Fase.PARADO:
		_terminar_ciclo()
	_fuera = false
