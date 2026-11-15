class_name FingerPose
extends SkeletonModifier3D
## Pose de los dedos encima de la animación: curl (0 abierta, 1 puño) por mano y pulgar arriba.
## Se aplica después de la animación y del IK, girando cada falange sobre su eje de flexión.

const FINGERS := ["index", "middle", "ring", "pinky"]

var curl := {"r": 0.0, "l": 0.0}
var thumb_up := {"r": false, "l": false}
var wrist_roll := {"r": 0.0, "l": 0.0} ## giro del antebrazo (supinación) en radianes
var curl_axis := Vector3(1, 0, 0) ## eje de flexión de las falanges (medido: X)
var thumb_axis := Vector3(1, 0, 0)
var max_angle := 1.45 ## radianes por falange con el puño cerrado


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for side in ["r", "l"]:
		var roll: float = wrist_roll[side]
		if absf(roll) > 0.001:
			var h := sk.find_bone("hand_" + side)
			sk.set_bone_pose_rotation(h, sk.get_bone_pose_rotation(h) * Quaternion(Vector3.UP, roll))
		var c: float = curl[side]
		if c <= 0.001:
			continue
		var sgn := 1.0 # los huesos de la mano izquierda ya vienen espejados en el modelo: mismo sentido de flexión
		for f in FINGERS:
			for k in [1, 2, 3]:
				var i := sk.find_bone("%s_%02d_%s" % [f, k, side])
				if i < 0:
					continue
				var q := sk.get_bone_pose_rotation(i) * Quaternion(curl_axis, c * max_angle * (0.8 if k == 1 else 1.0) * sgn)
				sk.set_bone_pose_rotation(i, q)
		var up: bool = thumb_up[side]
		for k in [2, 3]:
			var i := sk.find_bone("thumb_%02d_%s" % [k, side])
			if i >= 0:
				var a := (-0.2 if up else 0.9) * c * sgn
				sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * Quaternion(thumb_axis, a))
