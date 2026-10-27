extends Node3D
# ============================================================
# generadordecajas.gd   (nodo "GeneradorCajas" de la escena)
#  - Estantes CENTRADOS automáticamente en el almacén.
#  - 240 cajas base (6 filas x 8 módulos x 5 niveles = 240 huecos).
#  - Mes 7: los estantes se quedan vacíos (en reparación) y TODAS las
#    cajas se reparten tiradas por el suelo.
#  - Mes 8+: las cajas suben proporcionalmente (se llenan los mini
#    estantes extra que construye mundo_mes.gd).
# ============================================================

var caja_escena = preload("res://caja.tscn")

@export_group("Cajas")
@export var cajas_base: int = 240
## Actívalo para probar rápido con pocas cajas (ignora cajas_base).
@export var modo_prueba: bool = false
@export var cajas_prueba: int = 3

@export_group("Estantes")
@export var filas_estantes: int = 6
@export var repisas_por_mueble: int = 8
@export var niveles_altura: int = 5
## Largo de cada módulo. La caja mide 1.2 de largo, por eso 1.25 (antes 1.1 las solapaba).
@export var ancho_modulo_x: float = 1.25
@export var pasillo_z: float = 3.5
@export var alto_nivel: float = 1.0
## true = el bloque de estantes se centra solo en el piso del almacén.
@export var centrar_en_almacen: bool = true
## Solo se usan si centrar_en_almacen = false
@export var origen_x: float = -8.75
@export var origen_z: float = -4.4

const ANCHO_ESTANTE: float = 1.8
const ESTE_MES_PISO: String = "cajas_en_piso"

var _generacion: int = 0


func _ready() -> void:
	# Nos unimos al grupo para que el GameManager nos avise al cambiar de mes
	if not is_in_group("generadores_cajas"):
		add_to_group("generadores_cajas")

	var parent = get_parent()
	if parent:
		var camion_centro = parent.find_child("Camion3", true, false)
		if camion_centro:
			camion_centro.queue_free()

	if not caja_escena:
		print("❌ ERROR: No se pudo cargar 'caja.tscn'.")
		return

	generar_almacen_industrial()


# ------------------------------------------------------------
# DATOS PÚBLICOS (los usa mundo_mes.gd para soldadores y cintas)
# ------------------------------------------------------------
func capacidad_estantes() -> int:
	return filas_estantes * repisas_por_mueble * niveles_altura


func datos_estanterias() -> Array[Dictionary]:
	var o: Vector2 = _origen()
	var res: Array[Dictionary] = []
	var largo: float = repisas_por_mueble * ancho_modulo_x
	for f in range(filas_estantes):
		var x: float = o.x + f * pasillo_z
		var zc: float = o.y + (repisas_por_mueble - 1) * ancho_modulo_x * 0.5
		res.append({
			"centro": to_global(Vector3(x, 0.0, zc)),
			"largo": largo,
			"ancho": ANCHO_ESTANTE,
			"alto": niveles_altura * alto_nivel,
		})
	return res


# ------------------------------------------------------------
# CENTRADO
# ------------------------------------------------------------
func _centro_almacen_global() -> Vector3:
	var mundo = GameManager.mundo
	if mundo != null and mundo.has_method("limites_almacen"):
		var lim: AABB = mundo.limites_almacen()
		if lim.size.length() > 0.1:
			return lim.get_center()
	# Si el mundo aún no existe, medimos el nodo "Suelo" igual que mundo_mes.gd
	var suelo := get_tree().root.find_child("Suelo", true, false)
	if suelo != null:
		var hay: bool = false
		var total := AABB()
		var candidatos: Array = [suelo]
		candidatos.append_array(suelo.get_children())
		for c in candidatos:
			var mi := c as MeshInstance3D
			if mi != null and mi.mesh != null:
				var a: AABB = mi.global_transform * mi.get_aabb()
				total = a if not hay else total.merge(a)
				hay = true
		if hay:
			return total.get_center()
	return Vector3.ZERO


func _origen() -> Vector2:
	if not centrar_en_almacen:
		return Vector2(origen_x, origen_z)
	var c: Vector3 = to_local(_centro_almacen_global())
	# Ancho real del bloque: (filas-1)*pasillo + 1 estante. Largo: repisas * módulo.
	return Vector2(
		c.x - (filas_estantes - 1) * pasillo_z * 0.5,
		c.z - (repisas_por_mueble - 1) * ancho_modulo_x * 0.5)


# ------------------------------------------------------------
# GENERACIÓN
# ------------------------------------------------------------
func _cajas_objetivo() -> int:
	var n: int = cajas_prueba if modo_prueba else cajas_base
	return mini(n, capacidad_estantes()) if not _mes_en_piso() else n


func _mes_en_piso() -> bool:
	var mundo = GameManager.mundo
	if mundo != null:
		return bool(mundo.regla(GameManager.mes_actual, ESTE_MES_PISO, false))
	return false


func _esperar_mundo(mes: int) -> void:
	var intentos: int = 0
	while intentos < 180:
		var m = GameManager.mundo
		if m != null and m.listo_para_cajas(mes):
			return
		await get_tree().physics_frame
		intentos += 1
	push_warning("generadordecajas: el mundo no estuvo listo a tiempo (se generan solo las cajas de los estantes base).")


func generar_almacen_industrial() -> void:
	_generacion += 1
	var mi_id: int = _generacion
	var mes: int = GameManager.mes_actual

	# Meta provisional (se corrige al final con las cajas realmente creadas)
	GameManager.cajas_meta_mes = _cajas_objetivo()

	# Mes 7 y mes 8+ dependen de mundo_mes.gd (cajas al piso / estantes extra)
	if mes == 7 or mes >= 8:
		await _esperar_mundo(mes)
		if mi_id != _generacion:
			return

	var mundo = GameManager.mundo
	var en_piso: bool = mundo != null and bool(mundo.regla(mes, ESTE_MES_PISO, false))

	_construir_estanterias()

	# La física debe registrar los estantes nuevos antes de buscar huecos en el piso
	if en_piso:
		await get_tree().physics_frame
		await get_tree().physics_frame
		if mi_id != _generacion:
			return

	var cajas_creadas: int = 0
	var objetivo: int = cajas_prueba if modo_prueba else cajas_base

	if en_piso:
		cajas_creadas = _colocar_cajas_en_piso(mundo, objetivo)
	else:
		cajas_creadas = _colocar_cajas_en_estantes(mini(objetivo, capacidad_estantes()))
		# Mes 8 en adelante: mini estantes extra => más cajas (proporcional)
		if mes >= 8 and mundo != null:
			cajas_creadas += _colocar_cajas_en_extras(mundo, objetivo)

	print("📦 ¡Almacén listo para el Mes ", mes, "! Cajas generadas: ", cajas_creadas,
		"  (en el piso: ", en_piso, ")")

	# La meta del mes = cajas que realmente se generaron
	GameManager.cajas_meta_mes = cajas_creadas
	if mundo != null and mundo.has_method("verificar_capacidad_camiones"):
		mundo.verificar_capacidad_camiones(cajas_creadas)


func _construir_estanterias() -> void:
	# Limpiar cajas o estantes anteriores antes de generar los nuevos
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var o: Vector2 = _origen()

	var mat_repisa := StandardMaterial3D.new()
	mat_repisa.albedo_color = Color(0.15, 0.2, 0.35)
	var mat_poste := StandardMaterial3D.new()
	mat_poste.albedo_color = Color(0.1, 0.25, 0.55)

	var box_repisa := BoxMesh.new()
	box_repisa.size = Vector3(ANCHO_ESTANTE, 0.05, ancho_modulo_x)
	var forma_repisa := BoxShape3D.new()
	forma_repisa.size = box_repisa.size
	var box_poste := BoxMesh.new()
	box_poste.size = Vector3(ANCHO_ESTANTE, niveles_altura * alto_nivel, 0.08)

	for f in range(filas_estantes):
		var x_pos: float = o.x + (f * pasillo_z)

		var mueble_largo := StaticBody3D.new()
		mueble_largo.name = "Estanteria_Pasillo_" + str(f)
		mueble_largo.add_to_group("estantes")
		add_child(mueble_largo)

		for r in range(repisas_por_mueble):
			var z_pos: float = o.y + (r * ancho_modulo_x)

			for h in range(niveles_altura + 1):
				var mesh_repisa := MeshInstance3D.new()
				mesh_repisa.mesh = box_repisa
				mesh_repisa.material_override = mat_repisa
				mesh_repisa.position = Vector3(x_pos, h * alto_nivel, z_pos)
				mueble_largo.add_child(mesh_repisa)

				var col_repisa := CollisionShape3D.new()
				col_repisa.shape = forma_repisa
				col_repisa.position = mesh_repisa.position
				mueble_largo.add_child(col_repisa)

			if r == 0 or r == repisas_por_mueble - 1:
				var marco := MeshInstance3D.new()
				marco.mesh = box_poste
				marco.material_override = mat_poste
				var offset_z: float = -ancho_modulo_x / 2.0 if r == 0 else ancho_modulo_x / 2.0
				marco.position = Vector3(x_pos, (niveles_altura * alto_nivel) / 2.0, z_pos + offset_z)
				mueble_largo.add_child(marco)


func _nueva_caja() -> Node3D:
	return caja_escena.instantiate() as Node3D


func _colocar_cajas_en_estantes(cantidad: int) -> int:
	var o: Vector2 = _origen()
	var creadas: int = 0
	for f in range(filas_estantes):
		var x_pos: float = o.x + (f * pasillo_z)
		for r in range(repisas_por_mueble):
			var z_pos: float = o.y + (r * ancho_modulo_x)
			for h in range(niveles_altura):
				if creadas >= cantidad:
					return creadas
				var nueva_caja := _nueva_caja()
				nueva_caja.position = Vector3(x_pos, (h * alto_nivel) + 0.025, z_pos)
				add_child(nueva_caja)
				creadas += 1
	return creadas


func _colocar_cajas_en_extras(mundo, objetivo: int) -> int:
	var slots: Array[Transform3D] = mundo.slots_estantes_extra()
	var cantidad: int = slots.size()
	if modo_prueba:
		# Proporcional al modo prueba (los extras son ~15 % de la capacidad base)
		cantidad = mini(cantidad, maxi(1, int(ceil(objetivo * 0.15))))
	var creadas: int = 0
	for i in range(cantidad):
		var nueva_caja := _nueva_caja()
		add_child(nueva_caja)
		nueva_caja.global_transform = slots[i]
		creadas += 1
	return creadas


func _colocar_cajas_en_piso(mundo, cantidad: int) -> int:
	var puntos: Array[Vector3] = mundo.puntos_libres_cajas(cantidad)
	for p in puntos:
		var nueva_caja := _nueva_caja()
		add_child(nueva_caja)
		nueva_caja.global_position = p + Vector3(0, 0.02, 0)
		nueva_caja.rotation.y = randf() * TAU
	return puntos.size()
