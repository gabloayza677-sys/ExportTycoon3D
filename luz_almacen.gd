extends DirectionalLight3D

func _ready() -> void:
	actualizar_iluminacion()

func actualizar_iluminacion() -> void:
	if GameManager.mes_actual == 4:
		light_energy = 0.2  # Apagón parcial / penumbra en el Mes 4
		print("🔦 Almacén en modo penumbra por falla eléctrica (Mes 4)")
	else:
		light_energy = 1.0  # Luz normal
