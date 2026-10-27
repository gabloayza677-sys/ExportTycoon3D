extends CharacterBody3D
# ============================================================
# montacargas.gd  ->  res://montacargas.gd   (lo crea mundo_mes.gd)
# Montacargas pilotable (mes 10 en adelante).
#   F            subir / bajar
#   W S          avanzar / retroceder
#   A D          girar
#   R / V        subir / bajar la horquilla
#   Espacio      tomar / soltar un palet
# Al soltar un palet dentro de la zona amarilla se acomoda solo
# en la celda más cercana y se apila hasta 3 niveles.
# ============================================================

const VEL_MAX: float = 5.5
const VEL_ATRAS: float = 3.0
const ACEL: float = 5.0
const FRENO: float = 8.0
const GIRO: float = 1.5
const ALTURA_MIN: float = 0.08
const ALTURA_MAX: float = 2.6
const VEL_HORQUILLA: float = 0.9
const DIST_SUBIR: float = 3.2

var mundo = null                      # lo asigna mundo_mes.gd
var conductor = null
var vel_avance: float = 0.0
var altura_horquilla: float = ALTURA_MIN
var palet: RigidBody3D = null

var _horquilla: Node3D
var _zona: Area3D
var _baliza: OmniLight3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("montacargas")
	_construir()


func punto_asiento() -> Vector3:
	return global_transform * Vector3(0, 0.35, 0.45)


# ------------------------------------------------------------
# MODELO (procedural, como el de eventos_mes.gd)
# ------------------------------------------------------------
func _caja(padre: Node3D, tam: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = tam
	m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	m.position = pos
	padre.add_child(m)


func _construir() -> void:
	var amarillo := Color(0.95, 0.75, 0.1)
	var negro := Color(0.08, 0.08, 0.1)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.3, 1.5, 2.0)
	cs.shape = bs
	cs.position = Vector3(0, 0.75, 0.15)
	add_child(cs)

	_caja(self, Vector3(1.1, 0.7, 1.7), Vector3(0, 0.65, 0.2), amarillo)
	_caja(self, Vector3(0.5, 0.1, 0.5), Vector3(0, 0.98, 0.45), negro)
	_caja(self, Vector3(0.9, 0.06, 1.0), Vector3(0, 2.4, 0.42), negro)
	for sx in [-0.5, 0.5]:
		_caja(self, Vector3(0.06, 1.4, 0.06), Vector3(sx, 1.7, 0.0), negro)
		_caja(self, Vector3(0.06, 1.4, 0.06), Vector3(sx, 1.7, 0.85), negro)
	for sx in [-0.35, 0.35]:
		_caja(self, Vector3(0.1, 2.8, 0.1), Vector3(sx, 1.4, -0.95), negro)
	for sx in [-0.62, 0.62]:
		for sz in [-0.2, 0.8]:
			_caja(self, Vector3(0.22, 0.55, 0.55), Vector3(sx, 0.28, sz), negro)

	_horquilla = Node3D.new()
	_horquilla.position = Vector3(0, altura_horquilla, -1.0)
	add_child(_horquilla)
	_caja(_horquilla, Vector3(1.0, 0.5, 0.06), Vector3(0, 0.25, 0.0), negro)
	for sx in [-0.3, 0.3]:
		_caja(_horquilla, Vector3(0.12, 0.06, 1.3), Vector3(sx, 0.03, -0.65), negro)

	_zona = Area3D.new()
	var zs := CollisionShape3D.new()
	var zb := BoxShape3D.new()
	zb.size = Vector3(1.6, 0.9, 1.6)
	zs.shape = zb
	zs.position = Vector3(0, 0.45, -0.75)
	_zona.add_child(zs)
	_horquilla.add_child(_zona)

	_baliza = OmniLight3D.new()
	_baliza.light_color = Color(1.0, 0.6, 0.1)
	_baliza.omni_range = 9.0
	_baliza.position = Vector3(0, 2.6, 0.42)
	_baliza.add_to_group("inmune_apagon")
	add_child(_baliza)


# ------------------------------------------------------------
# ENTRADA
# ------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_F:
		_alternar_conduccion()
	elif k.keycode == KEY_SPACE and conductor != null:
		_tomar_o_soltar()


func _mensaje(t: String) -> void:
	if GameManager.hud != null:
		GameManager.hud.mensaje(t, 2.2)


func _alternar_conduccion() -> void:
	if conductor != null:
		desmontar()
		return
	var j = get_tree().get_first_node_in_group("jugador")
	if j == null or GameManager.en_transicion:
		return
	if j.global_position.distance_to(global_position) > DIST_SUBIR:
		return
	if j.caja_en_mano != null and j.caja_en_mano.visible:
		_mensaje("Entrega la caja antes de subir al montacargas")
		return
	conductor = j
	add_collision_exception_with(j)
	j.add_collision_exception_with(self)
	j.montar(self)


func desmontar() -> void:
	if conductor == null:
		return
	var salida: Vector3 = global_position + global_transform.basis.x * 1.7
	salida.y = global_position.y + 0.1
	remove_collision_exception_with(conductor)
	conductor.remove_collision_exception_with(self)
	conductor.desmontar(salida)
	conductor = null


# ------------------------------------------------------------
# PALETS
# ------------------------------------------------------------
func _tomar_o_soltar() -> void:
	if palet != null:
		_soltar()
		return
	var mejor: RigidBody3D = null
	var dmin: float = 999.0
	for c in _zona.get_overlapping_bodies():
		if c is RigidBody3D and c.is_in_group("palets"):
			var d: float = c.global_position.distance_to(_horquilla.global_position)
			if d < dmin:
				dmin = d
				mejor = c
	if mejor == null:
		_mensaje("Acerca la horquilla a un palet")
		return
	_tomar(mejor)


func _tomar(p: RigidBody3D) -> void:
	if p.has_meta("celda"):
		p.remove_meta("celda")
	p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	p.freeze = true
	p.collision_layer = 0
	p.collision_mask = 0
	p.reparent(_horquilla, true)
	p.transform = Transform3D(Basis(), Vector3(0, 0.06, -0.7))
	palet = p


func _soltar() -> void:
	var p: RigidBody3D = palet
	palet = null
	var escena := get_tree().current_scene
	p.reparent(escena if escena != null else get_tree().root, true)
	p.collision_layer = 1
	p.collision_mask = 1
	var colocado: bool = false
	if mundo != null:
		colocado = mundo.colocar_palet(p)
	if not colocado:
		p.freeze = false
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO


# ------------------------------------------------------------
# CONDUCCIÓN
# ------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var adelante: float = 0.0
	var giro: float = 0.0
	var mastil: float = 0.0
	if conductor != null and not GameManager.en_transicion and not get_tree().paused:
		if Input.is_key_pressed(KEY_W): adelante += 1.0
		if Input.is_key_pressed(KEY_S): adelante -= 1.0
		if Input.is_key_pressed(KEY_A): giro += 1.0
		if Input.is_key_pressed(KEY_D): giro -= 1.0
		if Input.is_key_pressed(KEY_R): mastil += 1.0
		if Input.is_key_pressed(KEY_V): mastil -= 1.0

	var objetivo: float = adelante * (VEL_MAX if adelante > 0.0 else VEL_ATRAS)
	var tasa: float = ACEL if adelante != 0.0 else FRENO
	vel_avance = move_toward(vel_avance, objetivo, tasa * delta)
	if absf(vel_avance) > 0.15:
		rotate_y(giro * GIRO * delta * signf(vel_avance))

	var frente: Vector3 = -global_transform.basis.z
	velocity.x = frente.x * vel_avance
	velocity.z = frente.z * vel_avance
	move_and_slide()
	if get_slide_collision_count() > 0 and get_real_velocity().length() < 0.2:
		vel_avance = 0.0

	altura_horquilla = clampf(altura_horquilla + mastil * VEL_HORQUILLA * delta, ALTURA_MIN, ALTURA_MAX)
	_horquilla.position.y = altura_horquilla

	# Baliza intermitente mientras alguien lo conduce
	var on: bool = conductor != null and fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.3
	_baliza.light_energy = 4.0 if on else 0.3
