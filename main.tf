# terraform init
# terraform plan / terraform apply
# terraform apply -var "VARIABLE_NAME=VARIABLE_VALUE" if terraform.tfvars !exists
# terraform destory

variable "subnet_prefix" {
    description = "CIDR block for the subnet"
    # type = any
    # default
}

provider "aws" {
    region = "AWS_DEFAULT_REGION"
    access_key = "AWS_ACCESS_KEY_ID"
    secret_key = "AWS_SECRET_ACCESS_KEY"
}

# 1. Create vpc
resource "aws_vpc" "secondary" {
    cidr_block = var.subnet_prefix
    tags = {
        Name= "secondary",
    }
}

# 2. Create internet gateway
resource "aws_internet_gateway" "secondary-gw"{
    vpc_id = aws_vpc.secondary.id 
    tags = {
        Name= "secondary",
    }
}

# 3. Create custom route table
resource "aws_route_table" "secondary-rt" {
    vpc_id = aws_vpc.secondary.id 

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.secondary-gw.id
    }
    
    tags = {
        Name= "secondary"
    }
}

# 4. Create a subnet
resource "aws_subnet" "secondary-subnet-1"{
    vpc_id = aws_vpc.secondary.id 

    cidr_block = "10.0.1.0/24"
    availability_zone = "" #example: "ap-southeast-1"

    tags = {
        Name= "secondary"
    }
}

# 5. Associate subnet with route table
resource "aws_route_table_association" "secondary-a"{
    subnet_id = aws_subnet.secondary-subnet-1.id
    route_table_id = aws_route_table.secondary-rt.id
}

# 6. Create security group to allow port 22,80,443
resource "aws_security_group" "secondary-allow-web"{
    name = "allow_web_traffic"
    description = "Allow Web inbound traffic"
    vpc_id = aws_vpc.secondary.id

    ingress{
        description = "HTTPS"
        from_port = 443
        to_port = 443
        protocol = "tcp"
        # cidr_blocks = [aws_vpc.secondary.cidr_block]
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress{
        description = "HTTP"
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress{
        description = "SSH"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress{
        from_port = 0
        to_port = 0
        protocol = "-1" #-1 = any protocol
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags = {
        Name = "secondary_allow_web"
    }
}

# 7. Create a network interface with an ip in the subnet created above
resource "aws_network_interface" "secondary_nic"{
    subnet_id = aws_subnet.secondary-subnet-1.id
    private_ips = ["10.0.1.50"]
    security_groups = [aws_security_group.secondary-allow-web.id]
}

# 8. Assign an elastic IP to the network interface created above
resource "aws_eip" "secondary-one"{
    vpc = true
    network_interface = aws_network_interface.secondary_nic.id
    associate_with_private_ip = "10.0.1.50"
    depends_on = [aws_internet_gateway.secondary-gw] #Telling terraform to execute eip after nic is created
}

# 9. Create Ubuntu server & install/enable apache2
resource "aws_instance" "secondary_web_server_instance"{
    ami = "ami-0fed77069cd5a6d6c"
    instance_type = "t2.micro"
    availability_zone = "" #example: "ap-southeast-1"
    key_name = "Singapore-EC2-KP"

    network_interface {
        network_interface_id = aws_network_interface.secondary_nic.id
        device_index = 0 #First network interface 
    }

    user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c 'echo Hello World web server > /var/www/html/index.html'
                EOF
    tags = {
        Name = "Secondary-web-server"
    }
}
