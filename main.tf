//aws provider

provider "aws" {
  region                  = "ap-south-1"
  profile                 = "default"
}

// VPC 

resource "aws_vpc" "VPC_Deployment" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "VPC_Deployment"
  }
}

//Public _SUBNET

resource "aws_subnet" "public_sub" {
  depends_on = [aws_vpc.VPC_Deployment]
  vpc_id     = aws_vpc.VPC_Deployment.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a" 
  map_public_ip_on_launch = true
  tags = {
    Name = "public_sub"
  }
}

//Private Subnet 

resource "aws_subnet" "private_sub" {
  vpc_id     = aws_vpc.VPC_Deployment.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-south-1a" 
  
  tags = {
    Name = "private_sub"
  }
}
 
// Internet Gateway for Public Subnet 

resource "aws_internet_gateway" "IG_VPC_Deployment" {

  vpc_id = aws_vpc.VPC_Deployment.id

  tags = {
    Name = "IG_VPC_Deployment"
  }
} 



// Route Table for  Internet Gateway of public_Sub to access internet

resource "aws_route_table" "RT_IG_public" {
  vpc_id = aws_vpc.VPC_Deployment.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IG_VPC_Deployment.id
  }

  tags = {
    Name = "RT_IG_public"
  }
}


//Assosiation Route Table with public subnet

resource "aws_route_table_association" "Assosiate_IG_RT" {
  subnet_id     = aws_subnet.public_sub.id
  route_table_id = aws_route_table.RT_IG_public.id
}


//eip for NAT gateway

resource "aws_eip" "NAT_eip" {
  vpc = true
}

// NAT gateway in public Subnet
resource "aws_nat_gateway" "NAT_gw" {
  depends_on = [
    aws_internet_gateway.IG_VPC_Deployment,
    aws_route_table.RT_IG_public
  ]
  allocation_id = aws_eip.NAT_eip.id
  subnet_id = aws_subnet.public_sub.id
}



//assosiate RT with  public Sub
resource "aws_route_table_association" "Assosiate_NAT_RT" {
  subnet_id     = aws_subnet.public_sub.id
  route_table_id = aws_route_table.RT_IG_public.id
}



// Route Table for NAT_gateway from private sub

resource "aws_route_table" "RT_NAT_private" {
  depends_on = [aws_route_table_association.Assosiate_NAT_RT]
  vpc_id = aws_vpc.VPC_Deployment.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.NAT_gw.id
  }

  tags = {
    Name = "RT_NAT_private"
  }
}

//
resource "aws_route_table_association" "Assosiate_NAT_RT_private" {
  subnet_id     = aws_subnet.private_sub.id
  route_table_id = aws_route_table.RT_NAT_private.id
}

//Security Group for 

//Security Group for Wordpress Instance
resource "aws_security_group" "SG_WordPress" {
  depends_on = [aws_vpc.VPC_Deployment,aws_route_table_association.Assosiate_NAT_RT]
  name        = "wordpress_http_ssh"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.VPC_Deployment.id
  revoke_rules_on_delete = "true"
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress{
    description = "SSH for VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "security_group_WordPress"
  }
}

//Secutiy Group for MySQL instance

resource "aws_security_group" "SG_MySQL" {
  depends_on = [aws_security_group.SG_WordPress]
  name        = "mysql_ssh"
  description = "Allow DB and SSH inbound traffic"
  vpc_id      = aws_vpc.VPC_Deployment.id
  revoke_rules_on_delete = "true"
  ingress {
    description = "DB from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    //security_groups = [aws_security_group.SG_WordPress.id]
  }

  ingress{
    description = "SSH for VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    //security_groups = [aws_security_group.SG_WordPress.id]
    cidr_blocks = ["0.0.0.0/0"]
  }
}



//Launch EC2 instance with MySQL
resource "aws_instance" "MySQL" {
  depends_on = [
    aws_security_group.SG_MySQL,

  ]
  ami           = "ami-052c08d70def0ac62"
  subnet_id   = aws_subnet.private_sub.id
  instance_type = "t2.micro"
  vpc_security_group_ids = ["${aws_security_group.SG_MySQL.id}"]
  //security_groups = ["${aws_security_group.SG_MySQL.name}"]
  key_name = "keypair_docker_webserver"
  tags = {
    name = "MySQL"
  }
}


//Launch EC2 instance with Wordpress
resource "aws_instance" "WordPress" {
  depends_on = [
    aws_security_group.SG_WordPress,
    aws_instance.MySQL
  ]
  ami           = "ami-052c08d70def0ac62"
  subnet_id   = aws_subnet.public_sub.id
  instance_type = "t2.micro"
  vpc_security_group_ids = ["${aws_security_group.SG_WordPress.id}"]
  //security_groups = ["${aws_security_group.SG_WordPress.name}"]
  key_name = "keypair_docker_webserver"
  tags = {
    name = "WordPress"
  }
}



//configure ansible 

resource "null_resource" "configure_remote1" {
  depends_on = [ aws_instance.WordPress ]
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("./keypair_docker_webserver.pem")
    host        = aws_instance.WordPress.public_ip
  }
  provisioner "remote-exec" {
  inline = [
    "sudo yum install python3 -y" ,
    "sudo yum install python3-pip -y" ,
    "sudo pip3 install ansible" ,
    "sudo mkdir /etc/ansible" ,
  ]
}
}


// copy sql instance files
resource "null_resource" "scp_private" {
  depends_on = [ null_resource.configure_remote1 ]
  provisioner "local-exec" {
    command = "scp -r -i keypair_docker_webserver.pem ./mysql_private/ ec2-user@${aws_instance.WordPress.public_ip}:/home/ec2-user/ "
  }
}

// configuration with ansible 

resource "null_resource" "configure_remote2" {
  depends_on = [ null_resource.scp_private ]
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("./keypair_docker_webserver.pem")
    host        = aws_instance.WordPress.public_ip
  }
   provisioner "remote-exec" {
     inline = [
      "ansible-playbook /home/ec2-user/mysql_private/wordpress-docker-play.yml",
      "sudo echo -e ''[mysql]'\n'${aws_instance.MySQL.private_ip}   ansible_ssh_user=ec2-user   ansible_ssh_private_key_file=/home/ec2-user/mysql_private/keypair_docker_webserver.pem'' > ./myhosts.txt",
      "sudo mv ./myhosts.txt  /etc/",
      "sudo mv /home/ec2-user/mysql_private/ansible.cfg /etc/ansible/ansible.cfg" ,
      "chmod 400 /home/ec2-user/mysql_private/keypair_docker_webserver.pem",
      //"sudo mv /home/ec2-user/mysql_private /root/",
      "ansible-playbook /home/ec2-user/mysql_private/mysql-docker-play.yml"
     ]
   }
  }

//start chrome
resource "null_resource" "nulllocal1"  { 
  depends_on = [ null_resource.configure_remote2 ]
  provisioner "local-exec" {
	    command = "start chrome http://${aws_instance.WordPress.public_ip}"
 	}
}

// print IP 
output "myos_ip" {
    value = aws_instance.WordPress.public_ip
}



