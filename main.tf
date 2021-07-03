resource "aws_elastic_beanstalk_application_version" "latest" {
  name        = "version-appver"
  application = aws_elastic_beanstalk_application.tftest.name
  description = "application version created by terraform"
  bucket      = "ebsapplications3bucketgn"
  key         = "app/deploy.zip"
  depends_on  = [aws_elastic_beanstalk_application.tftest]
}

resource "aws_elastic_beanstalk_application" "tftest" {
  name        = "tf-test-name"
  description = "tf-test-desc"
}

resource "aws_elastic_beanstalk_environment" "tfenvtest" {
    name                = "tf-test-name"
    application         = aws_elastic_beanstalk_application.tftest.name
    solution_stack_name = "64bit Amazon Linux 2 v5.4.1 running Node.js 14"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.test_profile.name
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.gnenv-vpc.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name  = "Subnets"
    value = join(",", [aws_subnet.gnenv-subnet-primary.id,aws_subnet.gnenv-subnet-secondary.id])
  }  

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value = join(",", [aws_subnet.gnenv-subnet-primary.id,aws_subnet.gnenv-subnet-secondary.id])
  }

setting {
    namespace = "aws:elb:listener:3000"
    name      = "InstancePort"
    value     = "3000"
  }

  setting {
    namespace = "aws:elb:loadbalancer"
    name      = "CrossZone"
    value     = "true"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBScheme"
    value     = "external"
  }

}

resource "aws_iam_instance_profile" "test_profile" {
  name = "test_profile"
  role = aws_iam_role.role.name
}

resource "aws_iam_role" "role" {
  name = "test_role"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_vpc" "gnenv-vpc" {
  cidr_block = "10.0.0.0/16"
}


resource "aws_internet_gateway" "gnenv-gw" {
  vpc_id = "${aws_vpc.gnenv-vpc.id}"
}

resource "aws_default_security_group" "gnenv_sg" {
  vpc_id      = "${aws_vpc.gnenv-vpc.id}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

}

resource "aws_security_group_rule" "gnenv_sg_rule" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["${aws_vpc.gnenv-vpc.cidr_block}"]
  security_group_id = "${aws_default_security_group.gnenv_sg.id}"
}

resource "aws_lb_target_group" "gnenvtargetgroup"{
  name     = "gnenvtarget-dev"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.gnenv-vpc.id}"
  target_type = "ip"
  depends_on = ["aws_lb.gnenvelb"]
}

resource "aws_subnet" "gnenv-subnet-primary" {
  vpc_id     = "${aws_vpc.gnenv-vpc.id}"
  cidr_block = "10.0.32.0/20"
  availability_zone = "eu-west-2a"
  map_public_ip_on_launch = true
}
resource "aws_subnet" "gnenv-subnet-secondary" {
  vpc_id     = "${aws_vpc.gnenv-vpc.id}"
  cidr_block = "10.0.48.0/20"
  availability_zone = "eu-west-2b"
  map_public_ip_on_launch = true
}

resource "aws_route_table" "gnenv_subnet_public" {
    vpc_id = "${aws_vpc.gnenv-vpc.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.gnenv-gw.id}"
    }
}

resource "aws_route_table_association" "gnenv_table_associations_1" {
    subnet_id = "${aws_subnet.gnenv-subnet-primary.id}"
    route_table_id = "${aws_route_table.gnenv_subnet_public.id}"
}
resource "aws_route_table_association" "gnenv_table_associations_2" {
    subnet_id = "${aws_subnet.gnenv-subnet-secondary.id}"
    route_table_id = "${aws_route_table.gnenv_subnet_public.id}"
}

resource "aws_lb" "gnenvelb"{
  name               = "gnenvelb-dev"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_default_security_group.gnenv_sg.id}"]
  subnets            = ["${aws_subnet.gnenv-subnet-primary.id}","${aws_subnet.gnenv-subnet-secondary.id}"]
}
resource "aws_lb_listener" "gnenv_listener" {
  load_balancer_arn = "${aws_lb.gnenvelb.id}"
  port              = "3000"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_lb_target_group.gnenvtargetgroup.id}"
    type             = "forward"
  }
}