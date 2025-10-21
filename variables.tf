variable "region"        { 
    type = string 
    default = "us-east-1" 
}
variable "vpc_cidr"      { 
    type = string  
    default = "10.0.0.0/16" 
}
variable "public_a_cidr" {
    type = string  
    default = "10.0.1.0/24" 
}
variable "public_b_cidr" { 
    type = string 
    default = "10.0.2.0/24" 
}
variable "app_port"      { 
    type = number 
    default = 8080
}
variable "cpu"           { 
    type = number  
    default = 256 
}   
variable "memory"        { 
    type = number  
    default = 512
} 

variable "project"  { 
    type = string 
    default = "ecs-fargate"
  
}