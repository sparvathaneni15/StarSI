output "cpu_public_ip" {
  value       = aws_eip.cpu.public_ip
  description = "The rendezvous address — what the phone, Pi, and Mac SSH to"
}

output "gpu_instance_id" {
  value       = aws_instance.gpu.id
  description = "Set as GPU_INSTANCE_ID in the capacity-controller values"
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}
