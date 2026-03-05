resource "time_static" "created_at" {}

resource "aws_s3_object" "hello" {
  count  = 3
  bucket  = aws_s3_bucket.my_testing_bucket.id
  key     = "${time_static.created_at.rfc3339}-${count.index}"
  content = "HELLO ROB @ ${time_static.created_at.rfc3339}"
}
