version = 1

cluster "localhost" {
  name        = "Localhost"
  description = "Simple cluster for testing & learning"
  hostname    = "localhost"
  port        = 3306
  profile     = "DEVELOPMENT"
}