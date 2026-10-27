extends Node
# ============================================================
# mundo_mes.gd  ->  res://mundo_mes.gd   (NO va en Globales; lo crea el GameManager)
#
# Construye el almacén (muros, techo, huecos, autopista) y aplica
# las mecánicas de cada mes: goteras, apagón, alarma, cuenta
# regresiva, auditores, soldadores, estantes extra, montacargas,
# palets y la evaluación del jefe.
# ============================================================

const Montacargas = preload("res://montacargas.gd")

# Reglas por mes. Los marcados como PERMANENTES siguen activos en meses posteriores.
const REGLAS: Dictionary = {
	2: {"goteras": true},
	3: {"carga_especial": true},
	4: {"apagon": true, "emergencia": true},
	5: {"cuenta_regresiva": 150.0, "cajas_express": 12},   # 2 min 30 s
	6: {"auditores": 3},
	7: {"cajas_en_piso": true, "soldadores": 4},
	8: {"estantes_extra": 4},
	9: {"emergencia": true},
	10: {"montacargas": true},
	11: {"aviso": "Tus acciones tienen consecuencias."},
	12: {"jefe": true},
}
const PERMANENTES: Array = ["estantes_extra", "montacargas"]

# Zona de palets (celdas) y palets
const ZONA_COLS: int = 4
const ZONA_FILAS: int = 3
const CELDA: Vector2 = Vector2(1.4, 1.1)
const NIVELES_MAX: int = 3
const PALET_ALTO: float = 0.9
const PATIO: float = 9.0          # franja de concreto entre el muro y la autopista
const CALZADA: float = 12.0       # ancho de la autopista
const EXTRA_ANCHO: float = 2.9    # mini estantes extra (mes 8+): caben 3 cajas por nivel
const EXTRA_FONDO: float = 1.3
const EXTRA_ALTO: float = 3.2

@export_group("Edificio")
@export var construir_edificio: bool = true
@export var luces_de_techo: bool = true
@export var alto_muro: float = 7.0
@export var alto_hueco: float = 4.6
@export var ancho_hueco: float = 5.8
@export var grosor_muro: float = 0.4
## Si lo dejas con tamaño 0 se mide solo a partir del nodo "Suelo".
@export var limites_manuales: AABB = AABB()
@export_group("Mecánicas")
@export var gotera_cantidad: int = 12
@export var palets_por_mes: int = 10
## Desde este mes (y mientras haya montacargas) NO se termina el mes con palets sin ordenar.
@export var palets_obligatorios_desde_mes: int = 10
@export_group("Entorno exterior")
@export var cielo_nublado: bool = true
@export var barrera_exterior: bool = true


# Patrulla simple para auditores (se mueve sola entre puntos al azar)
class Patrulla extends CharacterBody3D:
	var limites: AABB = AABB()
	var velocidad: float = 1.5
	var destino: Vector3 = Vector3.ZERO
	var espera: float = 0.0
	var atascado: float = 0.0
	var cooldown: float = 3.0
	var detenido: float = 0.0

	func _ready() -> void:
		_nuevo_destino()

	func _nuevo_destino() -> void:
		destino = Vector3(
			randf_range(limites.position.x + 3.0, limites.end.x - 3.0),
			global_position.y,
			randf_range(limites.position.z + 3.0, limites.end.z - 3.0))
		atascado = 0.0

	func _physics_process(delta: float) -> void:
		if not is_on_floor():
			velocity.y -= 20.0 * delta
		if detenido > 0.0 or espera > 0.0:
			detenido = maxf(0.0, detenido - delta)
			espera = maxf(0.0, espera - delta)
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			return
		var d: Vector3 = destino - global_position
		d.y = 0.0
		if d.length() < 1.0:
			espera = randf_range(1.0, 3.0)
			_nuevo_destino()
			return
		var dir: Vector3 = d.normalized()
		velocity.x = dir.x * velocidad
		velocity.z = dir.z * velocidad
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 6.0 * delta)
		move_and_slide()
		if get_real_velocity().length() < velocidad * 0.3:
			atascado += delta
			if atascado > 0.8:
				_nuevo_destino()
		else:
			atascado = 0.0


var _raiz: Node3D
var _lim: AABB
var _piso_y: float = 0.0
var _mes: int = 1

var _huecos: Array[Dictionary] = []          # {"pos": Vector3, "normal": Vector3}
var _dinamicos: Array[Node] = []             # se borran al cambiar de mes
var _mat_panel: StandardMaterial3D

# Apagón
var _apagon: bool = false
var _apagadas: Array[Light3D] = []
var _env_previo: Environment = null

# Alarma
var _alarma: Node3D = null
var _alarma_luces: Array[OmniLight3D] = []
var _mat_baliza: StandardMaterial3D
var _t_alarma: float = 0.0

# Cuenta regresiva
var _cuenta_activa: bool = false
var _cuenta_resta: float = 0.0
var _cuenta_base: int = 0

# NPCs procedurales
var _auditores: Array = []
var _luces_soldadura: Array = []
var _jefe: Node3D = null
var _wav_obturador: AudioStreamWAV = null

# Mes 8+ / mes 10+
var _estantes_extra_ok: bool = false
var _slots_extra: Array[Transform3D] = []
var _montacargas: CharacterBody3D = null
var _zona: Rect2 = Rect2()
var _zona_lista: bool = false

var _t_pistas: float = 0.0


# ============================================================
# ARRANQUE
# ============================================================
func iniciar() -> void:
	var escena := get_tree().current_scene
	_raiz = Node3D.new()
	_raiz.name = "MundoMes"
	(escena if escena != null else get_tree().root).add_child(_raiz)

	_calcular_limites()
	if construir_edificio:
		_construir_edificio()
		if luces_de_techo:
			_construir_luces_techo()
	if cielo_nublado:
		_construir_entorno()
	await aplicar_mes(GameManager.mes_actual)


func regla(mes: int, clave: String, defecto: Variant = null) -> Variant:
	if REGLAS.has(mes) and REGLAS[mes].has(clave):
		return REGLAS[mes][clave]
	if clave in PERMANENTES:
		for m in REGLAS.keys():
			if m <= mes and REGLAS[m].has(clave):
				return REGLAS[m][clave]
	return defecto


func regla_actual(clave: String, defecto: Variant = null) -> Variant:
	return regla(_mes, clave, defecto)


func apagon_activo() -> bool:
	return _apagon


func puede_interactuar() -> bool:
	var j = _jugador()
	return not (_apagon and j != null and not j.linterna_equipada)


func slots_estantes_extra() -> Array[Transform3D]:
	return _slots_extra


func _jugador():
	return get_tree().get_first_node_in_group("jugador")


func _camara() -> Camera3D:
	var j = _jugador()
	if j == null:
		return null
	return j.get_node_or_null("Camera3D") as Camera3D


func _hud():
	return GameManager.hud


# ============================================================
# CAMBIO DE MES
# ============================================================
func aplicar_mes(mes: int) -> void:
	# Esperamos a que la física registre los estantes recién generados
	await get_tree().physics_frame
	await get_tree().physics_frame

	_mes = mes
	_cuenta_activa = false
	desmontar_montacargas()
	_limpiar_dinamicos()

	if _hud() != null:
		_hud().ocultar_cuenta()
		_hud().set_mes(mes)
		_hud().aviso_permanente(str(regla(mes, "aviso", "")))

	# NPCs: invisibles hasta su mes (npc.gd decide con comprobar_visibilidad)
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc.has_method("comprobar_visibilidad"):
			npc.comprobar_visibilidad()

	_set_apagon(bool(regla(mes, "apagon", false)))
	_set_alarma(bool(regla(mes, "emergencia", false)))

	if regla(mes, "goteras", false):
		_crear_goteras()
	var n_aud: int = int(regla(mes, "auditores", 0))
	if n_aud > 0:
		_crear_auditores(n_aud)
	var n_sol: int = int(regla(mes, "soldadores", 0))
	if bool(regla(mes, "cajas_en_piso", false)):
		_bloquear_estantes()
	if n_sol > 0:
		_crear_soldadores(n_sol)
	if int(regla(mes, "estantes_extra", 0)) > 0:
		_construir_estantes_extra(int(regla(mes, "estantes_extra", 4)))
	if regla(mes, "montacargas", false):
		_preparar_montacargas()


# Lo llama el GameManager cuando termina el minievento y el diálogo
func comenzar_mes_activo() -> void:
	if _apagon:
		_barrer_luces_apagon()

	if _mes == 1 and _hud() != null:
		_hud().mensaje("Tus acciones tendrán consecuencias.", 4.5)

	var segs: float = float(regla(_mes, "cuenta_regresiva", 0.0))
	if segs > 0.0:
		_cuenta_resta = segs
		_cuenta_base = GameManager.cajas_procesadas_mes
		_cuenta_activa = true
		var n: int = int(regla(_mes, "cajas_express", 12))
		_hud().mostrar_cuenta("Envío prioritario · %d cajas" % n)

	if _mes == 10 and _hud() != null:
		_hud().mensaje("Hay un montacargas en el almacén y palets sueltos. Acércate y pulsa F.", 4.0)

	if regla(_mes, "jefe", false):
		_crear_jefe()


func _limpiar_dinamicos() -> void:
	for n in _dinamicos:
		if is_instance_valid(n):
			n.queue_free()
	_dinamicos.clear()
	_auditores.clear()
	_luces_soldadura.clear()
	_jefe = null


# ============================================================
# EDIFICIO: MUROS, TECHO, HUECOS Y AUTOPISTA
# ============================================================
func _calcular_limites() -> void:
	if limites_manuales.size.length() > 0.1:
		_lim = limites_manuales
	else:
		var suelo := get_tree().root.find_child("Suelo", true, false)
		var hay: bool = false
		var total := AABB()
		if suelo != null:
			var candidatos: Array = [suelo]
			candidatos.append_array(suelo.get_children())
			for c in candidatos:
				var mi := c as MeshInstance3D
				if mi != null and mi.mesh != null:
					var a: AABB = mi.global_transform * mi.get_aabb()
					total = a if not hay else total.merge(a)
					hay = true
		_lim = total if hay else AABB(Vector3(-20, 0, -30), Vector3(40, 0.1, 60))
	_piso_y = _lim.end.y
	print("🏭 Almacén: ", _lim, "  piso Y = ", _piso_y)


func _mat(color: Color, rugosidad: float = 0.9, emision: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rugosidad
	if emision > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emision
	return m


func _cubo(centro: Vector3, tam: Vector3, mat: Material, colision: bool = true, sombra: bool = true) -> Node3D:
	var cuerpo: Node3D
	if colision:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = tam
		cs.shape = bs
		sb.add_child(cs)
		cuerpo = sb
	else:
		cuerpo = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tam
	mi.mesh = bm
	mi.material_override = mat
	if not sombra:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cuerpo.add_child(mi)
	cuerpo.position = centro
	_raiz.add_child(cuerpo)
	return cuerpo


func _calcular_huecos() -> Dictionary:
	var res: Dictionary = {"-z": [], "+z": [], "-x": [], "+x": []}
	var minp: Vector3 = _lim.position
	var maxp: Vector3 = _lim.end
	for c in get_tree().root.find_children("Camion*", "Node3D", true, false):
		var sufijo: String = String(c.name).substr(6)
		if sufijo != "" and not sufijo.is_valid_int():
			continue
		var p: Vector3 = (c as Node3D).global_position
		var d: Dictionary = {
			"-z": absf(p.z - minp.z), "+z": absf(p.z - maxp.z),
			"-x": absf(p.x - minp.x), "+x": absf(p.x - maxp.x)}
		var mejor: String = "-z"
		for k in d:
			if d[k] < d[mejor]:
				mejor = k
		var coord: float = p.x if mejor.ends_with("z") else p.z
		var repetido: bool = false
		for otro in res[mejor]:
			if absf(float(otro) - coord) < ancho_hueco * 0.9:
				repetido = true
		if not repetido:
			res[mejor].append(coord)
	var vacio: bool = true
	for k in res:
		if not res[k].is_empty():
			vacio = false
	if vacio:
		res["+z"].append(_lim.get_center().x)   # sin camiones: un hueco por defecto
	return res


func _construir_edificio() -> void:
	var t: float = grosor_muro
	var minp: Vector3 = _lim.position
	var maxp: Vector3 = _lim.end
	var huecos: Dictionary = _calcular_huecos()

	_muro(0, minp.z - t * 0.5, minp.x - t, maxp.x + t, huecos["-z"])
	_muro(0, maxp.z + t * 0.5, minp.x - t, maxp.x + t, huecos["+z"])
	_muro(2, minp.x - t * 0.5, minp.z, maxp.z, huecos["-x"])
	_muro(2, maxp.x + t * 0.5, minp.z, maxp.z, huecos["+x"])

	for k in huecos:
		for c in huecos[k]:
			var coord: float = float(c)
			var pos: Vector3
			var normal: Vector3
			match k:
				"-z": pos = Vector3(coord, _piso_y, minp.z - t * 0.5); normal = Vector3(0, 0, -1)
				"+z": pos = Vector3(coord, _piso_y, maxp.z + t * 0.5); normal = Vector3(0, 0, 1)
				"-x": pos = Vector3(minp.x - t * 0.5, _piso_y, coord); normal = Vector3(-1, 0, 0)
				_:    pos = Vector3(maxp.x + t * 0.5, _piso_y, coord); normal = Vector3(1, 0, 0)
			_huecos.append({"pos": pos, "normal": normal})
		if not huecos[k].is_empty():
			_carretera(k)
			if barrera_exterior:
				_barrera_patio(k)

	# Techo (no proyecta sombra, para que el sol siga iluminando el interior)
	var cen := _lim.get_center()
	var mat_techo := _mat(Color(0.32, 0.34, 0.37), 0.8)
	_cubo(Vector3(cen.x, _piso_y + alto_muro + 0.2, cen.z),
		Vector3(_lim.size.x + t * 2.0, 0.4, _lim.size.z + t * 2.0), mat_techo, true, false)
	# Vigas del techo
	var mat_viga := _mat(Color(0.12, 0.12, 0.14), 0.7)
	var n_vigas: int = maxi(2, int(_lim.size.x / 8.0))
	for i in n_vigas + 1:
		var x: float = minp.x + _lim.size.x * float(i) / float(n_vigas)
		_cubo(Vector3(x, _piso_y + alto_muro - 0.25, cen.z), Vector3(0.35, 0.5, _lim.size.z), mat_viga, false, false)


func _muro(eje: int, fijo: float, desde: float, hasta: float, centros: Array) -> void:
	centros.sort()
	var cursor: float = desde
	var mitad: float = ancho_hueco * 0.5
	for c in centros:
		var a: float = maxf(float(c) - mitad, cursor)
		var b: float = minf(float(c) + mitad, hasta)
		if b <= a:
			continue
		_pieza_muro(eje, fijo, cursor, a, 0.0, alto_muro)
		_pieza_muro(eje, fijo, a, b, alto_hueco, alto_muro)    # dintel sobre el hueco
		cursor = b
	_pieza_muro(eje, fijo, cursor, hasta, 0.0, alto_muro)


func _pieza_muro(eje: int, fijo: float, a: float, b: float, y0: float, y1: float) -> void:
	var largo: float = b - a
	if largo < 0.05:
		return
	var alto: float = y1 - y0
	var medio: float = (a + b) * 0.5
	var cy: float = _piso_y + (y0 + y1) * 0.5
	var mat := _mat(Color(0.62, 0.63, 0.65), 0.95)
	if eje == 0:
		_cubo(Vector3(medio, cy, fijo), Vector3(largo, alto, grosor_muro), mat)
	else:
		_cubo(Vector3(fijo, cy, medio), Vector3(grosor_muro, alto, largo), mat)


func _carretera(clave: String) -> void:
	var horiz: bool = clave.ends_with("z")      # el muro corre a lo largo de X
	var signo: float = 1.0 if clave.begins_with("+") else -1.0
	var borde: float
	match clave:
		"+z": borde = _lim.end.z
		"-z": borde = _lim.position.z
		"+x": borde = _lim.end.x
		_:    borde = _lim.position.x
	var largo: float = (_lim.size.x if horiz else _lim.size.z) + 160.0
	var centro_largo: float = _lim.get_center().x if horiz else _lim.get_center().z
	var patio: float = PATIO
	var calzada: float = CALZADA
	var t: float = grosor_muro

	var asfalto := _mat(Color(0.14, 0.14, 0.16), 0.95)
	var patio_mat := _mat(Color(0.34, 0.34, 0.36), 0.95)
	var linea := _mat(Color(0.95, 0.95, 0.9), 0.8)

	for par in [[t + patio * 0.5, patio, patio_mat], [t + patio + calzada * 0.5, calzada, asfalto]]:
		var dist: float = par[0]
		var ancho: float = par[1]
		var pos: Vector3
		var tam: Vector3
		if horiz:
			pos = Vector3(centro_largo, _piso_y - 0.1, borde + signo * dist)
			tam = Vector3(largo, 0.2, ancho)
		else:
			pos = Vector3(borde + signo * dist, _piso_y - 0.1, centro_largo)
			tam = Vector3(ancho, 0.2, largo)
		_cubo(pos, tam, par[2], true, false)

	# Líneas de la autopista
	var dist_centro: float = t + patio + calzada * 0.5
	var n: int = int(largo / 8.0)
	for i in n:
		var u: float = centro_largo - largo * 0.5 + 4.0 + i * 8.0
		var p: Vector3
		var s: Vector3
		if horiz:
			p = Vector3(u, _piso_y + 0.012, borde + signo * dist_centro)
			s = Vector3(3.5, 0.02, 0.25)
		else:
			p = Vector3(borde + signo * dist_centro, _piso_y + 0.012, u)
			s = Vector3(0.25, 0.02, 3.5)
		_cubo(p, s, linea, false, false)
	for lado in [-1.0, 1.0]:
		var d2: float = t + patio + calzada * 0.5 + lado * (calzada * 0.5 - 0.5)
		if horiz:
			_cubo(Vector3(centro_largo, _piso_y + 0.012, borde + signo * d2), Vector3(largo, 0.02, 0.18), linea, false, false)
		else:
			_cubo(Vector3(borde + signo * d2, _piso_y + 0.012, centro_largo), Vector3(0.18, 0.02, largo), linea, false, false)


# ============================================================
# ENTORNO EXTERIOR: cielo nublado, terreno infinito y barreras
# ============================================================
const SHADER_CIELO: String = """
shader_type sky;
const vec3 C_CENIT = vec3(0.40, 0.45, 0.52);
const vec3 C_HORIZONTE = vec3(0.70, 0.72, 0.75);
const vec3 C_NUBE_OSCURA = vec3(0.36, 0.38, 0.42);
const vec3 C_NUBE_CLARA = vec3(0.86, 0.87, 0.89);
float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}
float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			 mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
	v += a * noise(p);
	p = p * 2.03 + vec2(17.1, 9.2);
	a *= 0.5;
  }
  return v;
}
void sky() {
  vec3 d = normalize(EYEDIR);
  if (d.y <= 0.0) {
	COLOR = C_HORIZONTE * 0.92;
  } else {
	vec3 base = mix(C_HORIZONTE, C_CENIT, pow(d.y, 0.55));
	vec2 uv = d.xz / (d.y + 0.22) * 1.7;
	float n = fbm(uv);
	float espesor = smoothstep(0.30, 0.72, n);
	vec3 nube = mix(C_NUBE_OSCURA, C_NUBE_CLARA, smoothstep(0.35, 0.85, fbm(uv * 1.9 + 3.7)));
	COLOR = mix(base, nube, espesor * 0.9);
	// en el horizonte todo se funde con la niebla
	COLOR = mix(COLOR, C_HORIZONTE * 0.92, 1.0 - smoothstep(0.0, 0.25, d.y));
  }
}
"""


func _construir_entorno() -> void:
	var sombra := Shader.new()
	sombra.code = SHADER_CIELO
	var mat_cielo := ShaderMaterial.new()
	mat_cielo.shader = sombra
	var cielo := Sky.new()
	cielo.sky_material = mat_cielo

	# Reutilizamos el Environment que ya exista (de la cámara o de un WorldEnvironment)
	var env: Environment = null
	var cam := _camara()
	if cam != null and cam.environment != null:
		env = cam.environment
	if env == null:
		for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			var we := n as WorldEnvironment
			if we != null and we.environment != null:
				env = we.environment
				break
	if env == null:
		env = Environment.new()
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.42, 0.44, 0.48)
		env.ambient_light_energy = 0.7
		var nuevo := WorldEnvironment.new()
		nuevo.name = "EntornoExterior"
		nuevo.environment = env
		_raiz.add_child(nuevo)

	env.background_mode = Environment.BG_SKY
	env.sky = cielo
	env.fog_enabled = true
	env.fog_light_color = Color(0.64, 0.66, 0.69)
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.0

	# Terreno enorme bajo todo: nunca se ve un vacío negro
	var cen: Vector3 = _lim.get_center()
	var terreno := _mat(Color(0.23, 0.25, 0.22), 1.0)
	_cubo(Vector3(cen.x, _piso_y - 0.5, cen.z), Vector3(6000.0, 0.4, 6000.0), terreno, true, false)


func _barrera(centro: Vector3, tam: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.name = "BarreraInvisible"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = tam
	cs.shape = bs
	sb.add_child(cs)
	sb.position = centro
	_raiz.add_child(sb)


# Cierra el patio exterior: el jugador puede salir al muelle a cargar, pero no más lejos
func _barrera_patio(clave: String) -> void:
	var horiz: bool = clave.ends_with("z")
	var signo: float = 1.0 if clave.begins_with("+") else -1.0
	var borde: float
	match clave:
		"+z": borde = _lim.end.z
		"-z": borde = _lim.position.z
		"+x": borde = _lim.end.x
		_:    borde = _lim.position.x
	var t: float = grosor_muro
	var d: float = t + PATIO + 0.25
	var alto: float = 8.0
	var cy: float = _piso_y + alto * 0.5
	var cen: Vector3 = _lim.get_center()
	var largo: float = (_lim.size.x if horiz else _lim.size.z) + t * 2.0
	if horiz:
		_barrera(Vector3(cen.x, cy, borde + signo * d), Vector3(largo + 1.0, alto, 0.5))
		for lado in [-1.0, 1.0]:
			_barrera(Vector3(cen.x + lado * (largo * 0.5 + 0.25), cy, borde + signo * d * 0.5), Vector3(0.5, alto, d))
	else:
		_barrera(Vector3(borde + signo * d, cy, cen.z), Vector3(0.5, alto, largo + 1.0))
		for lado in [-1.0, 1.0]:
			_barrera(Vector3(borde + signo * d * 0.5, cy, cen.z + lado * (largo * 0.5 + 0.25)), Vector3(d, alto, 0.5))


# Seguro extra: si algo cae al vacío, vuelve al almacén
func _vigilar_limites() -> void:
	var j = _jugador()
	if j != null and j.global_position.y < _piso_y - 4.0:
		j.global_position = (GameManager.spawn_transform.origin if GameManager.spawn_guardado else _lim.get_center()) + Vector3(0, 0.3, 0)
		j.velocity = Vector3.ZERO
	for p in get_tree().get_nodes_in_group("palets"):
		if p.global_position.y < _piso_y - 4.0 and p is RigidBody3D:
			var libre = _buscar_punto_libre(Vector2(1.4, 1.1), 0.5)
			if libre != null:
				p.linear_velocity = Vector3.ZERO
				p.global_position = libre + Vector3(0, 0.3, 0)


func _construir_luces_techo() -> void:
	var nx: int = clampi(int(round(_lim.size.x / 14.0)), 1, 4)
	var nz: int = clampi(int(round(_lim.size.z / 14.0)), 1, 4)
	_mat_panel = _mat(Color(1.0, 0.96, 0.88), 0.5, 2.5)
	for i in nx:
		for k in nz:
			var x: float = _lim.position.x + _lim.size.x * (i + 0.5) / nx
			var z: float = _lim.position.z + _lim.size.z * (k + 0.5) / nz
			var y: float = _piso_y + alto_muro - 0.5
			_cubo(Vector3(x, y, z), Vector3(2.2, 0.08, 0.5), _mat_panel, false, false)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.95, 0.85)
			l.light_energy = 0.9
			l.omni_range = 16.0
			l.shadow_enabled = false
			l.position = Vector3(x, y - 0.4, z)
			l.add_to_group("luces_techo")
			_raiz.add_child(l)


# ============================================================
# APAGÓN (mes 4): oscuridad total, solo sirve la linterna (tecla 1)
# ============================================================
func _env_negro() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.BLACK
	e.ambient_light_energy = 0.0
	return e


func _set_apagon(on: bool) -> void:
	var cam := _camara()
	if on == _apagon:
		return
	_apagon = on
	if on:
		if cam != null:
			if cam.environment != null and cam.environment != _env_previo:
				_env_previo = cam.environment
			cam.environment = _env_negro()
		_barrer_luces_apagon()
		for l in get_tree().get_nodes_in_group("luces_techo"):
			(l as Light3D).visible = false
		if _mat_panel != null:
			_mat_panel.emission_enabled = false
	else:
		if cam != null:
			cam.environment = _env_previo
		for l in _apagadas:
			if is_instance_valid(l):
				l.visible = true
		_apagadas.clear()
		for l in get_tree().get_nodes_in_group("luces_techo"):
			(l as Light3D).visible = true
		if _mat_panel != null:
			_mat_panel.emission_enabled = true


func _barrer_luces_apagon() -> void:
	for n in get_tree().root.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if l == null or l.is_in_group("inmune_apagon") or l.is_in_group("luces_techo"):
			continue
		if l.visible:
			l.visible = false
			_apagadas.append(l)


# ============================================================
# ALARMA DE EMERGENCIA (techo): balizas rojas + sirena intermitente
# ============================================================
func _set_alarma(on: bool) -> void:
	if on and _alarma == null:
		_alarma = Node3D.new()
		_alarma.name = "AlarmaEmergencia"
		_raiz.add_child(_alarma)
		_mat_baliza = _mat(Color(1.0, 0.1, 0.08), 0.4, 0.0)
		_mat_baliza.emission_enabled = true
		_mat_baliza.emission = Color(1.0, 0.1, 0.08)
		var y: float = _piso_y + alto_muro - 0.35
		var esquinas: Array = [
			Vector2(_lim.position.x + 5.0, _lim.position.z + 5.0),
			Vector2(_lim.end.x - 5.0, _lim.position.z + 5.0),
			Vector2(_lim.position.x + 5.0, _lim.end.z - 5.0),
			Vector2(_lim.end.x - 5.0, _lim.end.z - 5.0)]
		for e in esquinas:
			var m := MeshInstance3D.new()
			var cil := CylinderMesh.new()
			cil.top_radius = 0.22
			cil.bottom_radius = 0.28
			cil.height = 0.35
			m.mesh = cil
			m.material_override = _mat_baliza
			m.position = Vector3(e.x, y, e.y)
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_alarma.add_child(m)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.12, 0.08)
			l.omni_range = 18.0
			l.light_energy = 0.0
			l.position = Vector3(e.x, y - 0.4, e.y)
			l.add_to_group("inmune_apagon")
			_alarma.add_child(l)
			_alarma_luces.append(l)
		var sirena := AudioStreamPlayer3D.new()
		sirena.stream = _crear_wav_sirena()
		sirena.unit_size = 40.0
		sirena.max_distance = 220.0
		sirena.volume_db = -6.0
		sirena.position = Vector3(_lim.get_center().x, y, _lim.get_center().z)
		_alarma.add_child(sirena)
		sirena.play()
		_t_alarma = 0.0
	elif not on and _alarma != null:
		_alarma.queue_free()
		_alarma = null
		_alarma_luces.clear()


func _actualizar_alarma(delta: float) -> void:
	if _alarma == null:
		return
	_t_alarma += delta
	var prendida: bool = fmod(_t_alarma, 0.6) < 0.4     # 0.4 s ON / 0.2 s OFF = ritmo de la sirena
	for l in _alarma_luces:
		l.light_energy = 7.0 if prendida else 0.0
	_mat_baliza.emission_energy_multiplier = 4.0 if prendida else 0.0


func _crear_wav_sirena() -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = int(rate * 1.2)
	var datos := PackedByteArray()
	datos.resize(n * 2)
	var fase: float = 0.0
	for i in n:
		var t: float = float(i) / rate
		var local: float = fmod(t, 0.6)
		var f: float = 880.0 if t < 0.6 else 660.0
		fase += TAU * f / rate
		var v: float = 0.0
		if local < 0.4:
			v = sin(fase) * 0.45 * clampf(local / 0.01, 0.0, 1.0) * clampf((0.4 - local) / 0.01, 0.0, 1.0)
		datos.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = datos
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


func _crear_wav_obturador() -> AudioStreamWAV:
	if _wav_obturador != null:
		return _wav_obturador
	var rate: int = 22050
	var n: int = int(rate * 0.12)
	var datos := PackedByteArray()
	datos.resize(n * 2)
	for i in n:
		var t: float = float(i) / rate
		var v: float = (randf() * 2.0 - 1.0) * exp(-t * 45.0) * 0.6
		if t < 0.012:
			v += sin(TAU * 1800.0 * t) * 0.5 * (1.0 - t / 0.012)
		datos.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = datos
	_wav_obturador = w
	return w


# ============================================================
# GOTERAS (mes 2): gotas constantes durante todo el mes
# ============================================================
func _crear_goteras() -> void:
	var y_techo: float = _piso_y + alto_muro - 0.05
	var vida: float = sqrt(2.0 * (y_techo - _piso_y) / 9.8)    # llegan al piso justo al morir
	var mat_gota := StandardMaterial3D.new()
	mat_gota.albedo_color = Color(0.62, 0.8, 1.0, 0.8)
	mat_gota.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_gota.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mat_charco := StandardMaterial3D.new()
	mat_charco.albedo_color = Color(0.3, 0.45, 0.6, 0.55)
	mat_charco.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_charco.roughness = 0.05
	mat_charco.metallic = 0.3

	for i in gotera_cantidad:
		var x: float = randf_range(_lim.position.x + 3.0, _lim.end.x - 3.0)
		var z: float = randf_range(_lim.position.z + 3.0, _lim.end.z - 3.0)

		var g := CPUParticles3D.new()
		g.amount = 3 + (i % 3)
		g.lifetime = vida
		g.preprocess = vida
		g.direction = Vector3(0, -1, 0)
		g.spread = 0.0
		g.initial_velocity_min = 0.0
		g.initial_velocity_max = 0.0
		g.gravity = Vector3(0, -9.8, 0)
		g.local_coords = false
		var gota := SphereMesh.new()
		gota.radius = 0.02
		gota.height = 0.08
		gota.material = mat_gota
		g.mesh = gota
		g.position = Vector3(x, y_techo, z)
		_raiz.add_child(g)
		_dinamicos.append(g)

		var charco := MeshInstance3D.new()
		var cil := CylinderMesh.new()
		cil.top_radius = 0.4
		cil.bottom_radius = 0.4
		cil.height = 0.008
		charco.mesh = cil
		charco.material_override = mat_charco
		charco.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		charco.position = Vector3(x, _piso_y + 0.006, z)
		charco.scale = Vector3(0.3, 1.0, 0.3)
		_raiz.add_child(charco)
		_dinamicos.append(charco)
		charco.create_tween().tween_property(charco, "scale", Vector3(1.6, 1.0, 1.6), 200.0)


# ============================================================
# CUENTA REGRESIVA (mes 5: "cada segundo cuenta", 2:30)
# ============================================================
func _actualizar_cuenta(delta: float) -> void:
	if not _cuenta_activa or GameManager.en_transicion:
		return
	_cuenta_resta -= delta
	_hud().actualizar_cuenta(_cuenta_resta)
	var hechas: int = GameManager.cajas_procesadas_mes - _cuenta_base
	var meta: int = int(regla(_mes, "cajas_express", 12))
	if hechas >= meta:
		_cuenta_activa = false
		_hud().ocultar_cuenta()
		_hud().mensaje("El camión prioritario salió a tiempo.", 3.0)
		HonorManager.modificar_honor(5, "Envío prioritario cumplido")
	elif _cuenta_resta <= 0.0:
		_cuenta_activa = false
		_hud().ocultar_cuenta()
		_hud().mensaje("El camión prioritario se fue sin su carga.", 3.5)
		_hud().destello(0.35)
		HonorManager.modificar_honor(-10, "Envío prioritario perdido")


# ============================================================
# PERSONAJES PROCEDURALES
# ============================================================
func _malla_caja(padre: Node3D, tam: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = tam
	m.mesh = b
	m.material_override = _mat(color)
	m.position = pos
	padre.add_child(m)


func _humanoide(camisa: Color, pantalon: Color, casco: Color = Color(0, 0, 0, 0)) -> Node3D:
	var raiz := Node3D.new()
	_malla_caja(raiz, Vector3(0.34, 0.8, 0.22), Vector3(0, 0.4, 0), pantalon)
	_malla_caja(raiz, Vector3(0.52, 0.68, 0.3), Vector3(0, 1.14, 0), camisa)
	_malla_caja(raiz, Vector3(0.14, 0.62, 0.14), Vector3(-0.35, 1.12, 0), camisa)
	_malla_caja(raiz, Vector3(0.14, 0.62, 0.14), Vector3(0.35, 1.12, 0), camisa)
	var cab := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	cab.mesh = sm
	cab.material_override = _mat(Color(0.85, 0.65, 0.52))
	cab.position = Vector3(0, 1.63, 0)
	raiz.add_child(cab)
	if casco.a > 0.0:
		var c := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = 0.19
		cm.height = 0.26
		c.mesh = cm
		c.material_override = _mat(casco)
		c.position = Vector3(0, 1.7, 0)
		raiz.add_child(c)
	return raiz


# ------------------------------------------------------------
# AUDITORES (mes 6): patrullan y toman fotos
# ------------------------------------------------------------
func _crear_auditores(n: int) -> void:
	for i in n:
		var p = _buscar_punto_libre(Vector2(1.0, 1.0), 0.4)
		if p == null:
			continue
		var a := Patrulla.new()
		a.limites = _lim
		a.velocidad = randf_range(1.3, 1.8)
		a.cooldown = randf_range(3.0, 6.0)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.8
		cs.shape = cap
		cs.position = Vector3(0, 0.9, 0)
		a.add_child(cs)
		var cuerpo := _humanoide(Color(0.85, 0.9, 0.2), Color(0.25, 0.27, 0.3), Color(0.92, 0.92, 0.92))
		a.add_child(cuerpo)
		_malla_caja(cuerpo, Vector3(0.2, 0.13, 0.12), Vector3(0.1, 1.32, -0.24), Color(0.05, 0.05, 0.06))
		var flash := OmniLight3D.new()
		flash.name = "Flash"
		flash.light_energy = 0.0
		flash.omni_range = 10.0
		flash.position = Vector3(0.1, 1.45, -0.35)
		flash.add_to_group("inmune_apagon")
		a.add_child(flash)
		var snd := AudioStreamPlayer3D.new()
		snd.name = "Obturador"
		snd.stream = _crear_wav_obturador()
		snd.unit_size = 8.0
		a.add_child(snd)
		a.position = p
		_raiz.add_child(a)
		_auditores.append(a)
		_dinamicos.append(a)


func _actualizar_auditores(delta: float) -> void:
	var j = _jugador()
	if j == null or _auditores.is_empty() or GameManager.en_transicion:
		return
	var espacio := _raiz.get_world_3d().direct_space_state
	for a in _auditores:
		if not is_instance_valid(a):
			continue
		a.cooldown -= delta
		if a.cooldown > 0.0:
			continue
		var cabeza: Vector3 = a.global_position + Vector3(0, 1.5, 0)
		var objetivo: Vector3 = j.global_position + Vector3(0, 1.4, 0)
		var hacia: Vector3 = objetivo - cabeza
		if hacia.length() > 9.0:
			continue
		var frente: Vector3 = -a.global_transform.basis.z
		if frente.dot(hacia.normalized()) < 0.35:
			continue
		var consulta := PhysicsRayQueryParameters3D.create(cabeza, objetivo)
		var excluir: Array[RID] = [a.get_rid(), j.get_rid()]
		consulta.exclude = excluir
		if not espacio.intersect_ray(consulta).is_empty():
			continue
		_fotografiar(a, j)


func _fotografiar(a, j) -> void:
	a.cooldown = randf_range(6.0, 11.0)
	a.detenido = 0.9
	var flash := a.get_node_or_null("Flash") as OmniLight3D
	if flash != null:
		flash.light_energy = 14.0
		flash.create_tween().tween_property(flash, "light_energy", 0.0, 0.18)
	var snd := a.get_node_or_null("Obturador") as AudioStreamPlayer3D
	if snd != null:
		snd.play()
	if j.global_position.distance_to(a.global_position) < 6.5:
		_hud().destello(0.4)
	if j.corriendo_actual:
		HonorManager.modificar_honor(-3, "Un auditor te fotografió corriendo")


# ------------------------------------------------------------
# SOLDADORES (mes 7)
# ------------------------------------------------------------
func _datos_estanterias() -> Array:
	var g := get_tree().get_first_node_in_group("generadores_cajas")
	if g != null and g.has_method("datos_estanterias"):
		return g.datos_estanterias()
	return []


## Dónde trabaja cada soldador: de pie en el pasillo, frente a un estante distinto.
func _puestos_soldadores(n: int) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	var filas: Array = _datos_estanterias()
	if filas.is_empty() or n <= 0:
		return res
	for i in n:
		var idx: int = mini(int((i + 0.5) * filas.size() / n), filas.size() - 1)
		var fila: Dictionary = filas[idx]
		var lado: float = 1.0 if i % 2 == 0 else -1.0
		var c: Vector3 = fila["centro"]
		var largo: float = fila["largo"]
		var frac: float = fmod(0.31 + i * 0.37, 1.0) - 0.5
		res.append({
			"pos": Vector3(c.x + lado * 1.15, _piso_y, c.z + frac * (largo - 2.5)),
			"rot": lado * PI * 0.5,
			"altura": 0.8 + float(i % 3) * 0.45,
		})
	return res


func posiciones_soldadores() -> Array[Vector3]:
	var res: Array[Vector3] = []
	if int(regla(GameManager.mes_actual, "soldadores", 0)) <= 0:
		return res
	for p in _puestos_soldadores(int(regla(GameManager.mes_actual, "soldadores", 0))):
		res.append(p["pos"])
	return res


func _crear_soldadores(n: int) -> void:
	var mat_chispa := StandardMaterial3D.new()
	mat_chispa.albedo_color = Color(1.0, 0.65, 0.15)
	mat_chispa.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var puestos: Array[Dictionary] = _puestos_soldadores(n)
	for i in n:
		var pos: Vector3
		var rot: float = randf() * TAU
		var altura: float = 0.25
		if i < puestos.size():
			pos = puestos[i]["pos"]
			rot = puestos[i]["rot"]
			altura = puestos[i]["altura"]
		else:
			var p = _buscar_punto_libre(Vector2(1.6, 1.6), 0.5)
			if p == null:
				continue
			pos = p
		var s := StaticBody3D.new()
		s.name = "Soldador"
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.7
		cs.shape = cap
		cs.position = Vector3(0, 0.85, 0)
		s.add_child(cs)
		s.position = pos
		s.rotation.y = rot
		var h := _humanoide(Color(0.75, 0.4, 0.1), Color(0.2, 0.25, 0.35), Color(1.0, 0.5, 0.05))
		h.rotation.x = -0.55                        # inclinado sobre el trabajo
		s.add_child(h)
		_malla_caja(s, Vector3(0.07, 0.07, 0.35), Vector3(0.12, altura, -0.6), Color(0.3, 0.3, 0.32))   # soplete
		var ch := CPUParticles3D.new()
		ch.amount = 40
		ch.lifetime = 0.55
		ch.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		ch.emission_sphere_radius = 0.04
		ch.direction = Vector3(0, 1, 0)
		ch.spread = 65.0
		ch.initial_velocity_min = 1.5
		ch.initial_velocity_max = 3.8
		ch.gravity = Vector3(0, -9.8, 0)
		ch.local_coords = false
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.02, 0.02)
		bm.material = mat_chispa
		ch.mesh = bm
		ch.position = Vector3(0.12, altura, -0.8)
		s.add_child(ch)
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.65, 0.25)
		luz.omni_range = 7.0
		luz.position = Vector3(0.12, altura + 0.2, -0.8)
		s.add_child(luz)
		_raiz.add_child(s)
		_dinamicos.append(s)
		_luces_soldadura.append(luz)


## Mes 7: todos los estantes en reparación (cinta + cartel). No llevan cajas.
func _bloquear_estantes() -> void:
	var cinta := _mat(Color(0.95, 0.75, 0.05), 0.7)
	for fila in _datos_estanterias():
		var c: Vector3 = fila["centro"]
		var largo: float = fila["largo"]
		for lado in [-1.0, 1.0]:
			for y in [0.9, 1.8]:
				_dinamicos.append(_cubo(Vector3(c.x + lado * 1.0, _piso_y + y, c.z), Vector3(0.03, 0.12, largo), cinta, false, false))
			var cartel := Label3D.new()
			cartel.text = "EN REPARACIÓN"
			cartel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			cartel.font_size = 40
			cartel.pixel_size = 0.006
			cartel.outline_size = 10
			cartel.modulate = Color(1.0, 0.8, 0.15)
			cartel.position = Vector3(c.x, _piso_y + 2.4, c.z + lado * (largo * 0.5 + 0.5))
			_raiz.add_child(cartel)
			_dinamicos.append(cartel)


func _actualizar_soldadores() -> void:
	for l in _luces_soldadura:
		if is_instance_valid(l):
			l.light_energy = randf_range(0.5, 4.5)


# ------------------------------------------------------------
# JEFE (mes 12)
# ------------------------------------------------------------
func _punto_entrada() -> Vector3:
	if _huecos.is_empty():
		return _lim.position + Vector3(0, 0, -6)
	var h: Dictionary = _huecos[0]
	return h["pos"] + h["normal"] * 5.0


func _crear_jefe() -> void:
	if _jefe != null and is_instance_valid(_jefe):
		return
	var jefe := Node3D.new()
	var cuerpo := _humanoide(Color(0.1, 0.1, 0.14), Color(0.08, 0.08, 0.1))
	jefe.add_child(cuerpo)
	_malla_caja(cuerpo, Vector3(0.06, 0.35, 0.02), Vector3(0, 1.15, -0.16), Color(0.8, 0.1, 0.1))   # corbata
	_malla_caja(cuerpo, Vector3(0.3, 0.4, 0.04), Vector3(0.38, 0.95, -0.2), Color(0.55, 0.55, 0.58))  # carpeta
	jefe.position = _punto_entrada()
	jefe.position.y = _piso_y
	_raiz.add_child(jefe)
	_jefe = jefe
	_dinamicos.append(jefe)

	var centro: Vector3 = GameManager.spawn_transform.origin
	var espera = _buscar_punto_libre(Vector2(1.0, 1.0), 0.4, centro, 10.0)
	if espera == null:
		espera = centro + Vector3(0, 0, -6.0)
	_hud().mensaje("El jefe ha llegado al almacén.", 3.0)
	await _caminar(jefe, espera, 2.4)


func _caminar(nodo: Node3D, destino: Vector3, vel: float) -> void:
	var t: float = 0.0
	while is_instance_valid(nodo):
		var d: Vector3 = destino - nodo.global_position
		d.y = 0.0
		if d.length() < 0.08:
			break
		var dt: float = get_process_delta_time()
		var dir: Vector3 = d.normalized()
		nodo.global_position += dir * minf(vel * dt, d.length())
		nodo.rotation.y = lerp_angle(nodo.rotation.y, atan2(-dir.x, -dir.z), 0.15)
		t += dt
		var cuerpo := nodo.get_child(0) as Node3D
		if cuerpo != null:
			cuerpo.position.y = absf(sin(t * 7.0)) * 0.05
		await get_tree().process_frame
	if is_instance_valid(nodo) and nodo.get_child_count() > 0:
		(nodo.get_child(0) as Node3D).position.y = 0.0


# Lo llama el GameManager al completar el mes 12
func auditoria_final() -> void:
	desmontar_montacargas()
	var j = _jugador()
	var cam := _camara()
	if j == null or cam == null:
		return
	if _jefe == null or not is_instance_valid(_jefe):
		_jefe = null
		await _crear_jefe()
	var frente: Vector3 = -cam.global_transform.basis.z
	frente.y = 0.0
	frente = frente.normalized()
	var destino: Vector3 = j.global_position + frente * 2.4
	destino.y = _piso_y
	_hud().mensaje("El jefe se acerca a evaluar tu trabajo.", 3.0)
	await _caminar(_jefe, destino, 3.2)
	var dir: Vector3 = j.global_position - _jefe.global_position
	_jefe.rotation.y = atan2(-dir.x, -dir.z)
	await get_tree().create_timer(1.2).timeout
	await _hud().mostrar_evaluacion(HonorManager.evaluar_final())


# ============================================================
# BÚSQUEDA DE ESPACIO LIBRE (para estantes, palets, NPCs, cajas en el piso)
# ============================================================
func _buscar_punto_libre(tam: Vector2, margen: float = 0.6, centro: Vector3 = Vector3.ZERO,
		radio: float = 0.0, evitar: Rect2 = Rect2(), intentos: int = 250) -> Variant:
	var espacio := _raiz.get_world_3d().direct_space_state
	var forma := BoxShape3D.new()
	forma.size = Vector3(tam.x + margen * 2.0, 1.4, tam.y + margen * 2.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = forma
	var j = _jugador()
	if j != null:
		var excluir: Array[RID] = [j.get_rid()]
		q.exclude = excluir
	for i in intentos:
		var x: float
		var z: float
		if radio > 0.0:
			var ang: float = randf() * TAU
			var r: float = sqrt(randf()) * radio
			x = centro.x + cos(ang) * r
			z = centro.z + sin(ang) * r
		else:
			x = randf_range(_lim.position.x + 2.0, _lim.end.x - 2.0)
			z = randf_range(_lim.position.z + 2.0, _lim.end.z - 2.0)
		if x < _lim.position.x + 1.5 or x > _lim.end.x - 1.5 or z < _lim.position.z + 1.5 or z > _lim.end.z - 1.5:
			continue
		if evitar.size.x > 0.0 and evitar.has_point(Vector2(x, z)):
			continue
		var cerca_puerta: bool = false
		for h in _huecos:
			if Vector2(h["pos"].x, h["pos"].z).distance_to(Vector2(x, z)) < 7.0:
				cerca_puerta = true
		if cerca_puerta:
			continue
		q.transform = Transform3D(Basis(), Vector3(x, _piso_y + 0.9, z))
		if espacio.intersect_shape(q, 1).is_empty():
			return Vector3(x, _piso_y, z)
	return null


## Para el generador de cajas (mes 7: cajas tiradas por el piso).
func puntos_libres(n: int, tam: Vector2 = Vector2(1.0, 1.0)) -> Array[Vector3]:
	var res: Array[Vector3] = []
	for i in n:
		var p = _buscar_punto_libre(tam, 0.25)
		if p != null:
			res.append(p)
	return res


# ============================================================
# API PARA EL GENERADOR DE CAJAS, LOS CAMIONES Y EL GAMEMANAGER
# ============================================================
func limites_almacen() -> AABB:
	return _lim


func listo_para_cajas(mes: int) -> bool:
	if _raiz == null:
		return false
	if int(regla(mes, "estantes_extra", 0)) > 0 and not _estantes_extra_ok:
		return false
	return true


## Mes 7: cajas tiradas por el suelo, sin solaparse y lejos de puertas, soldadores y spawn.
func puntos_libres_cajas(n: int, separacion: float = 1.6) -> Array[Vector3]:
	var res: Array[Vector3] = []
	if _raiz == null:
		return res
	var espacio := _raiz.get_world_3d().direct_space_state
	var forma := BoxShape3D.new()
	forma.size = Vector3(1.3, 1.2, 1.6)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = forma
	var j = _jugador()
	if j != null:
		var excluir: Array[RID] = [j.get_rid()]
		q.exclude = excluir
	var reservados: Array[Vector2] = []
	for p in posiciones_soldadores():
		reservados.append(Vector2(p.x, p.z))
	if GameManager.spawn_guardado:
		reservados.append(Vector2(GameManager.spawn_transform.origin.x, GameManager.spawn_transform.origin.z))

	var intentos: int = 0
	while res.size() < n and intentos < n * 80:
		intentos += 1
		var pt := Vector2(
			randf_range(_lim.position.x + 1.5, _lim.end.x - 1.5),
			randf_range(_lim.position.z + 1.5, _lim.end.z - 1.5))
		var libre: bool = true
		for r in res:
			if Vector2(r.x, r.z).distance_to(pt) < separacion:
				libre = false
				break
		if not libre:
			continue
		for r in reservados:
			if r.distance_to(pt) < 2.2:
				libre = false
				break
		if not libre:
			continue
		for h in _huecos:
			if Vector2(h["pos"].x, h["pos"].z).distance_to(pt) < 7.0:
				libre = false
				break
		if not libre:
			continue
		q.transform = Transform3D(Basis(), Vector3(pt.x, _piso_y + 0.7, pt.y))
		if espacio.intersect_shape(q, 1).is_empty():
			res.append(Vector3(pt.x, _piso_y, pt.y))
	if res.size() < n:
		push_warning("Solo hay espacio para %d de %d cajas en el piso. Agranda el almacén o baja 'separacion'." % [res.size(), n])
	return res


func hueco_mas_cercano(pos: Vector3) -> Dictionary:
	var mejor: Dictionary = {}
	var dmin: float = INF
	for h in _huecos:
		var d: float = Vector2(h["pos"].x, h["pos"].z).distance_to(Vector2(pos.x, pos.z))
		if d < dmin:
			dmin = d
			mejor = h
	return mejor


## Distancia desde el plano del muro hasta el centro del carril de la autopista.
func distancia_carril() -> float:
	return grosor_muro * 0.5 + PATIO + CALZADA * 0.5


func verificar_capacidad_camiones(total: int) -> void:
	var cap: int = 0
	var n: int = 0
	for z in get_tree().get_nodes_in_group("zonas_entrega"):
		if z.has_method("capacidad"):
			cap += z.capacidad()
			n += 1
	if n == 0:
		return
	if cap <= 0:
		push_warning("Los camiones no tienen espacio de carga (revisa el CollisionShape3D de cada Area3D).")
	elif cap >= total:
		print("🚚 Capacidad de los camiones: ", cap, " cajas por viaje. Las ", total, " cajas del mes caben en un solo viaje.")
	else:
		print("🚚 Capacidad de los camiones: ", cap, " cajas por viaje. Las ", total, " cajas se despachan en ",
			ceili(float(total) / cap), " viajes (cada camión sale lleno y vuelve vacío).")


# ---------- PALETS: condición para terminar el mes ----------
func palets_pendientes() -> int:
	var n: int = 0
	for p in get_tree().get_nodes_in_group("palets"):
		if not p.has_meta("ordenado"):
			n += 1
	return n


func requiere_palets() -> bool:
	var m: int = GameManager.mes_actual
	return m >= palets_obligatorios_desde_mes and bool(regla(m, "montacargas", false))


## El GameManager debe llamarla antes de cerrar el mes: true = se puede avanzar.
func mes_completable() -> bool:
	if not requiere_palets():
		return true
	return palets_pendientes() == 0


func avisar_palets_pendientes() -> void:
	if _hud() != null:
		_hud().mensaje("Aún quedan %d palets sin ordenar. Llévalos a la zona amarilla." % palets_pendientes(), 3.5)


func _faltan_solo_palets() -> bool:
	return requiere_palets() and not GameManager.en_transicion \
		and GameManager.cajas_meta_mes > 0 \
		and GameManager.cajas_procesadas_mes >= GameManager.cajas_meta_mes \
		and palets_pendientes() > 0


# ============================================================
# ESTANTES EXTRA (mes 8 en adelante, permanentes)
# ============================================================
func _construir_estantes_extra(n: int) -> void:
	if _estantes_extra_ok:
		return
	_estantes_extra_ok = true
	for i in n:
		var p = _buscar_punto_libre(Vector2(EXTRA_ANCHO, EXTRA_FONDO), 0.9)
		if p == null:
			push_warning("No hay espacio libre para el estante extra %d. Ajusta limites_manuales." % i)
			continue
		_crear_estante(p)


func _crear_estante(pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.name = "EstanteExtra"
	sb.add_to_group("estantes_extra")
	sb.add_to_group("estantes")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(EXTRA_ANCHO, EXTRA_ALTO, EXTRA_FONDO)
	cs.shape = bs
	cs.position = Vector3(0, EXTRA_ALTO * 0.5, 0)
	sb.add_child(cs)
	var metal := Color(0.15, 0.3, 0.6)
	var tabla := Color(0.75, 0.55, 0.15)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_malla_caja(sb, Vector3(0.08, EXTRA_ALTO, 0.08), Vector3(sx * (EXTRA_ANCHO * 0.5 - 0.05), EXTRA_ALTO * 0.5, sz * (EXTRA_FONDO * 0.5 - 0.05)), metal)
	# Tablas cada 1.0 m (igual que los estantes grandes): la caja mide 0.85 de alto
	for y in [0.15, 1.15, 2.15, 3.15]:
		_malla_caja(sb, Vector3(EXTRA_ANCHO, 0.06, EXTRA_FONDO - 0.1), Vector3(0, y, 0), tabla)
	sb.position = pos
	_raiz.add_child(sb)
	# Posiciones de almacenamiento (sobre cada tabla): 3 niveles x 3 columnas = 9 cajas
	for y in [0.18, 1.18, 2.18]:
		for x in [-0.93, 0.0, 0.93]:
			_slots_extra.append(sb.global_transform * Transform3D(Basis(), Vector3(x, y, 0)))


# ============================================================
# MONTACARGAS Y PALETS (mes 10 en adelante, permanentes)
# ============================================================
func desmontar_montacargas() -> void:
	if _montacargas != null and is_instance_valid(_montacargas) and _montacargas.conductor != null:
		_montacargas.desmontar()


func _preparar_montacargas() -> void:
	if not _zona_lista:
		_crear_zona_palets()
	if _montacargas == null or not is_instance_valid(_montacargas):
		var centro: Vector3 = GameManager.spawn_transform.origin
		var p = _buscar_punto_libre(Vector2(1.6, 2.6), 0.5, centro, 14.0)
		if p == null:
			p = _buscar_punto_libre(Vector2(1.6, 2.6), 0.3)
		if p == null:
			push_warning("No hay espacio libre para el montacargas.")
			return
		var m := Montacargas.new()
		m.mundo = self
		m.position = p + Vector3(0, 0.05, 0)
		_raiz.add_child(m)
		_montacargas = m
	_generar_palets()


func _crear_zona_palets() -> void:
	var w: float = ZONA_COLS * CELDA.x
	var h: float = ZONA_FILAS * CELDA.y
	var p = _buscar_punto_libre(Vector2(w, h), 0.4)
	if p == null:
		push_warning("No encontré espacio para la zona de palets (%.1f x %.1f m)." % [w, h])
		return
	_zona = Rect2(Vector2(p.x - w * 0.5, p.z - h * 0.5), Vector2(w, h))
	_zona_lista = true
	var base := _mat(Color(0.12, 0.12, 0.13), 0.9)
	var amarillo := _mat(Color(0.95, 0.8, 0.1), 0.8)
	_cubo(Vector3(p.x, _piso_y + 0.004, p.z), Vector3(w + 0.4, 0.01, h + 0.4), base, false, false)
	for i in ZONA_COLS + 1:
		_cubo(Vector3(_zona.position.x + i * CELDA.x, _piso_y + 0.012, p.z), Vector3(0.07, 0.01, h), amarillo, false, false)
	for k in ZONA_FILAS + 1:
		_cubo(Vector3(p.x, _piso_y + 0.012, _zona.position.y + k * CELDA.y), Vector3(w, 0.01, 0.07), amarillo, false, false)


func _generar_palets() -> void:
	for i in palets_por_mes:
		var p = _buscar_punto_libre(Vector2(1.4, 1.1), 0.5, Vector3.ZERO, 0.0, _zona.grow(1.5) if _zona_lista else Rect2())
		if p == null:
			break
		_crear_palet(p)


func _crear_palet(pos: Vector3) -> void:
	var p := RigidBody3D.new()
	p.name = "Palet"
	p.mass = 60.0
	p.add_to_group("palets")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.2, PALET_ALTO, 0.8)
	cs.shape = bs
	cs.position = Vector3(0, PALET_ALTO * 0.5, 0)
	p.add_child(cs)
	_malla_caja(p, Vector3(1.2, 0.14, 0.8), Vector3(0, 0.07, 0), Color(0.62, 0.45, 0.22))
	var carga := Color(0.72, 0.55, 0.35).lerp(Color(0.6, 0.45, 0.3), randf())
	_malla_caja(p, Vector3(1.05, 0.7, 0.7), Vector3(0, 0.5, 0), carga)
	p.set_meta("t_spawn", Time.get_ticks_msec() / 1000.0)
	p.position = pos + Vector3(0, 0.02, 0)
	p.rotation.y = randf_range(-0.4, 0.4)
	_raiz.add_child(p)
	HonorManager.registrar_palet_generado(1)


## Lo llama el montacargas al soltar un palet. true = quedó acomodado en la zona.
func colocar_palet(p: RigidBody3D) -> bool:
	if not _zona_lista:
		return false
	var pos: Vector3 = p.global_position
	if not _zona.grow(0.8).has_point(Vector2(pos.x, pos.z)):
		return false

	# Ocupación de cada celda
	var ocupacion: Dictionary = {}
	for q in get_tree().get_nodes_in_group("palets"):
		if q == p or not q.has_meta("celda"):
			continue
		var c: Vector2i = q.get_meta("celda")
		ocupacion[c] = int(ocupacion.get(c, 0)) + 1

	# Celda libre más cercana al punto donde lo soltaron
	var mejor: Vector2i = Vector2i(-1, -1)
	var dmin: float = 1.0e9
	for ix in ZONA_COLS:
		for iz in ZONA_FILAS:
			var cel := Vector2i(ix, iz)
			if int(ocupacion.get(cel, 0)) >= NIVELES_MAX:
				continue
			var cx: float = _zona.position.x + (ix + 0.5) * CELDA.x
			var cz: float = _zona.position.y + (iz + 0.5) * CELDA.y
			var d: float = Vector2(cx, cz).distance_to(Vector2(pos.x, pos.z))
			if d < dmin:
				dmin = d
				mejor = cel
	if mejor.x < 0:
		_hud().mensaje("La zona de palets está llena", 2.0)
		return false

	var nivel: int = int(ocupacion.get(mejor, 0))
	var px: float = _zona.position.x + (mejor.x + 0.5) * CELDA.x
	var pz: float = _zona.position.y + (mejor.y + 0.5) * CELDA.y
	p.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	p.freeze = true
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO
	p.global_transform = Transform3D(Basis(), Vector3(px, _piso_y + 0.02 + nivel * PALET_ALTO, pz))
	p.set_meta("celda", mejor)

	if not p.has_meta("ordenado"):
		p.set_meta("ordenado", true)
		var seg: float = Time.get_ticks_msec() / 1000.0 - float(p.get_meta("t_spawn", 0.0))
		HonorManager.registrar_palet_ordenado(seg)
		_hud().mensaje("Palet ordenado", 1.4)
		# Si ya no quedan cajas ni palets, el mes puede cerrarse
		if GameManager.cajas_meta_mes > 0 and GameManager.cajas_procesadas_mes >= GameManager.cajas_meta_mes \
				and palets_pendientes() == 0:
			GameManager.call_deferred("comprobar_fin_de_mes")
	return true


# ============================================================
# BUCLE
# ============================================================
func _process(delta: float) -> void:
	if _raiz == null:
		return
	_actualizar_alarma(delta)
	_actualizar_cuenta(delta)
	_actualizar_auditores(delta)
	_actualizar_soldadores()

	_t_pistas += delta
	if _t_pistas >= 0.2:
		_t_pistas = 0.0
		_actualizar_pistas()
		_vigilar_limites()


func _actualizar_pistas() -> void:
	var j = _jugador()
	if j == null or _hud() == null:
		return
	var txt: String = ""
	if j.vehiculo != null:
		txt = "W A S D  conducir   ·   R / V  horquilla   ·   Espacio  tomar / soltar palet   ·   F  bajar"
	elif _apagon and not j.linterna_equipada:
		txt = "Pulsa  1  para equipar la linterna"
	elif _montacargas != null and is_instance_valid(_montacargas) \
			and j.global_position.distance_to(_montacargas.global_position) < 3.2:
		txt = "F  subir al montacargas"
	if _faltan_solo_palets():
		var falta: String = "Faltan %d palets por ordenar" % palets_pendientes()
		txt = falta if txt == "" else txt + "   ·   " + falta
	_hud().set_pista(txt)
