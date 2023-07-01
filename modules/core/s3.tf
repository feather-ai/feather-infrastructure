resource "aws_s3_bucket" "front_storage" {
  bucket = "${var.prefix}-front-storage"
  acl    = "private"

  tags = {
    Name        = "Loading Bay"
  }
}

# Disable all public access from the loading bay
resource "aws_s3_bucket_public_access_block" "loadingbay-block-public" {
  bucket = aws_s3_bucket.front_storage.id

  block_public_acls   = true
  block_public_policy = true
}