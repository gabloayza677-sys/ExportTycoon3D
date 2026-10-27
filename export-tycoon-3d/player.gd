extends CharacterBody3D

signal stamina_cambiada(valor: float, maximo: float)

@export var SPEED: float = 5.0
@export var SPRINT_MULT: float = 1.55
@export var JUMP_VELOCITY: float = 4.5
@export var MOUSE_SENSITIVITY: float = 0.003

# --- Stamina ---
const STAMINA_MAX: float = 100.0
const COSTO_CORRER: float = 14.0       # por segundo
const COSTO_CARGA: float = 2.5         # por segundo, caminando con caja
const COSTO_SALTO: float = 6.0
const REGEN: float = 16.0
const UMBRAL_RECUPERACION: float = 25.0
const MES_CARGA_ESPECIAL: int = 3

@onready var camera: Camera3D = $Camera3D

var caja_en_mano: Node3D = null
var tiempo_caminata: float = 0.0
var pos_inicial_mano: Vector3 = Vector3(0, -0.45, -0.65)

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var stamina: float = STAMINA_MAX
var agotado: bool = false
var corriendo_actual: bool = false
var linterna: SpotLight3D = null
var linterna_equipada: bool = false
var vehiculo: Node3D = null            # montacargas que está pilotando (mes 10+)
var _ultimo_emitido: float = -1.0


func _ready() -> void:
	add_to_group("jugador")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	caja_en_mano = camera.get_node_or_null("CajaEnMano")
	if not caja_en_mano:
		caja_en_mano = Node3D.new()
		caja_en_mano.name = "CajaEnMano"
		camera.add_child(caja_en_mano)

	caja_en_mano.position = pos_inicial_mano
	caja_en_mano.visible = false

	construir_caja_y_manos_fov()
	crear_crosshair()
	_crear_linterna()


# ------------------------------------------------------------
# LINTERNA (tecla 1)
# ------------------------------------------------------------
func _crear_linterna() -> void:
	linterna = SpotLight3D.new()
	linterna.name = "Linterna"
	linterna.spot_range = 30.0
	linterna.spot_angle = 30.0
	linterna.spot_attenuation = 0.7
	linterna.light_energy = 7.0
	linterna.light_color = Color(1.0, 0.96, 0.85)
	linterna.shadow_enabled = true
	linterna.position = Vector3(0.18, -0.15, -0.1)
	linterna.visible = false
	linterna.add_to_group("inmune_apagon")   # el apagón no la apaga
	camera.add_child(linterna)


func alternar_linterna() -> void:
	linterna_equipada = not linterna_equipada
	linterna.visible = linterna_equipada


func construir_caja_y_manos_fov() -> void:
	if not caja_en_mano:
		return

	for child in caja_en_mano.get_children():
		child.queue_free()

	var mat_carton = StandardMaterial3D.new()
	mat_carton.albedo_color = Color(0.85, 0.85, 0.85)
	mat_carton.roughness = 0.9

	var textura_logos = load("res://caja.jpg")
	if textura_logos:
		mat_carton.albedo_texture = textura_logos

	var caja_modelo = MeshInstance3D.new()
	caja_modelo.name = "CajaFov"

	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1.0, 0.8, 1.2)
	caja_modelo.mesh = box_mesh
	caja_modelo.material_override = mat_carton

	caja_modelo.scale = Vector3(0.38, 0.38, 0.38)
	caja_modelo.position = Vector3(0, -0.05, 0)
	caja_modelo.rotation_degrees = Vector3(-8, 5, 0)
	caja_en_mano.add_child(caja_modelo)

	var mat_piel = StandardMaterial3D.new()
	mat_piel.albedo_color = Color(0.85, 0.65, 0.52)
	mat_piel.roughness = 1.0

	var box_mano = BoxMesh.new()
	box_mano.size = Vector3(0.1, 0.12, 0.4)

	var mano_izq = MeshInstance3D.new()
	mano_izq.mesh = box_mano
	mano_izq.material_override = mat_piel
	mano_izq.position = Vector3(-0.35, -0.05, 0.05)
	mano_izq.rotation_degrees = Vector3(15, -15, 20)
	caja_en_mano.add_child(mano_izq)

	var mano_der = MeshInstance3D.new()
	mano_der.mesh = box_mano
	mano_der.material_override = mat_piel
	mano_der.position = Vector3(0.35, -0.05, 0.05)
	mano_der.rotation_degrees = Vector3(15, 15, -20)
	caja_en_mano.add_child(mano_der)


func crear_crosshair() -> void:
	if not has_node("CanvasLayer"):
		var canvas = CanvasLayer.new()
		canvas.name = "CanvasLayer"
		add_child(canvas)

		var crosshair = ColorRect.new()
		crosshair.name = "Crosshair"
		crosshair.color = Color(1, 1, 1, 0.9)
		crosshair.size = Vector2(3, 3)
		crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crosshair.set_anchors_preset(Control.PRESET_CENTER)
		crosshair.offset_left = -1.5
		crosshair.offset_top = -1.5
		crosshair.offset_right = 1.5
		crosshair.offset_bottom = 1.5

		canvas.add_child(crosshair)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		if camera:
			camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
			camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1 or event.keycode == KEY_KP_1:
			alternar_linterna()

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------
# MONTACARGAS (lo llama montacargas.gd)
# ------------------------------------------------------------
func montar(v: Node3D) -> void:
	vehiculo = v
	if caja_en_mano:
		caja_en_mano.visible = false


func desmontar(pos: Vector3) -> void:
	vehiculo = null
	global_position = pos
	velocity = Vector3.ZERO


# ------------------------------------------------------------
# STAMINA
# ------------------------------------------------------------
func _carga_especial_activa() -> bool:
	return GameManager.mes_actual == MES_CARGA_ESPECIAL


func _actualizar_stamina(delta: float, corriendo: bool, cargando: bool, moviendose: bool) -> void:
	var especial: bool = cargando and _carga_especial_activa()
	var gasto: float = 0.0
	if corriendo:
		gasto += COSTO_CORRER
	if cargando and moviendose:
		gasto += COSTO_CARGA * (2.5 if especial else 1.0)   # mes 3: consumo x2.5
	if especial and not moviendose:
		gasto += 2.0                                         # sostenerla también cansa

	if gasto > 0.0:
		stamina = maxf(0.0, stamina - gasto * delta)
	else:
		var regen: float = REGEN * (0.5 if cargando else 1.0)
		stamina = minf(STAMINA_MAX, stamina + regen * delta)

	if stamina <= 0.0:
		agotado = true
	elif agotado and stamina >= UMBRAL_RECUPERACION:
		agotado = false

	if absf(stamina - _ultimo_emitido) > 0.05:
		_ultimo_emitido = stamina
		stamina_cambiada.emit(stamina, STAMINA_MAX)


func _factor_velocidad(cargando: bool) -> float:
	var f: float = 1.0
	if agotado:
		f *= 0.55
	if cargando and _carga_especial_activa():
		f *= 0.5                     # mes 3: carga especial = movimiento muy lento
	if GameManager.mundo != null and GameManager.mundo.apagon_activo() and not linterna_equipada:
		f *= 0.4                     # mes 4: a ciegas sin linterna
	return f


func _physics_process(delta: float) -> void:
	# Pilotando el montacargas: el jugador solo sigue al asiento y mira alrededor
	if vehiculo != null:
		velocity = Vector3.ZERO
		global_position = vehiculo.punto_asiento()
		corriendo_actual = false
		_actualizar_stamina(delta, false, false, false)
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor() and not agotado:
		velocity.y = JUMP_VELOCITY
		stamina = maxf(0.0, stamina - COSTO_SALTO)

	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		input_dir.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		input_dir.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		input_dir.x += 1

	input_dir = input_dir.normalized()
	var direction := (transform.basis * input_dir)

	var moviendose: bool = direction.length() > 0.1
	var cargando: bool = caja_en_mano != null and caja_en_mano.visible
	corriendo_actual = Input.is_key_pressed(KEY_SHIFT) and moviendose and not agotado and is_on_floor()

	var vel: float = SPEED * _factor_velocidad(cargando)
	if corriendo_actual:
		vel *= SPRINT_MULT

	_actualizar_stamina(delta, corriendo_actual, cargando, moviendose)

	if direction:
		velocity.x = direction.x * vel
		velocity.z = direction.z * vel
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	if caja_en_mano and caja_en_mano.visible:
		if is_on_floor() and velocity.length() > 0.1:
			tiempo_caminata += delta * 10.0
			var sway_y = sin(tiempo_caminata) * 0.015
			var sway_x = cos(tiempo_caminata * 0.5) * 0.01
			caja_en_mano.position = pos_inicial_mano + Vector3(sway_x, sway_y, 0)
		else:
			caja_en_mano.position = caja_en_mano.position.lerp(pos_inicial_mano, delta * 5.0)

	move_and_slide()
