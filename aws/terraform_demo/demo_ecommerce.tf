##############################################################################
# HashiCorp Product Demo - ecommerce site - Apache, MySQL, Tomcat, Apache
##############################################################################

provider "aws" {
  region = "${var.region}"
}

# Step 1 - Stand up cloud instance(s)
resource "aws_instance" "spacelysprockets" {
  ami                    = "${var.demoami}"
  instance_type          = "${var.ecommerce_instance_type}"
  key_name               = "${var.key_name}"
  count                  = "${var.ecommerce_servers}"
  vpc_security_group_ids = ["${aws_security_group.ecommerce_sg.id}"]

  # This puts one server in each subnet, up to the total number of subnets.
  #subnet_id = "${lookup(var.subnets, count.index % var.ecommerce_servers)}"
  # This just crams them all in one subnet
  subnet_id = "${var.subnets[0]}"

  # This is the provisioning user
  #connection {
  #    user = "${var.user}"
  #    private_key = "${var.private_ssh_key}"
  #}

  # AWS Instance Tags
  tags {
    Name  = "${var.ecomTagName}-${var.subdomain}-${count.index}"
    owner = "scarolan@hashicorp.com"
    TTL   = "120"
  }

  ## Install Chef
  #provisioner "remote-exec" {
  #    inline = [
  #    "curl https://omnitruck.chef.io/install.sh | sudo bash -s -- -c current -P chefdk"
  #    ]
  #}

  # # Install the development web server stack
  #provisioner "remote-exec" {
  #    scripts = [
  #        "${path.module}/../../shared/scripts/run_chef_dev.sh"
  #    ]
  #}
}

resource "aws_security_group" "ecommerce_sg" {
  name        = "ecommerce_sg_${var.subdomain}"
  description = "Ecommerce website security group"
  vpc_id      = "${var.vpc_id}"

  # AWS Instance Tags
  tags {
    Name = "${var.subdomain}-sg"
  }

  // These are for internal traffic
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "udp"
    self      = true
  }

  // HTTP traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // HTTPS traffic
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // For remote access via SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // This is for outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# # Step 2 - Create two more machines and a load balancer
# # Uncomment and `terraform apply` to continue the demo...
resource "aws_lb" "ecom_lb" {
  name            = "ecommerce-${var.subdomain}-lb"
  internal        = false
  security_groups = ["${aws_security_group.ecommerce_sg.id}"]
  subnets         = ["${var.subnets[0]}", "${var.subnets[1]}", "${var.subnets[2]}"]

  tags = {
    Name  = "ecommerce_ecom_lb"
    owner = "scarolan@hashicorp.com"
    TTL   = "8"
  }
}

# # Create a target group
resource "aws_lb_target_group" "ecom_tg" {
  name     = "ecommerce-${var.subdomain}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${var.vpc_id}"

  stickiness = {
    type    = "lb_cookie"
    enabled = true
  }

  health_check = {
    interval            = 30
    path                = "/index.html"
    port                = 80
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

# # Create a listener on port 80
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = "${aws_lb.ecom_lb.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_lb_target_group.ecom_tg.arn}"
    type             = "forward"
  }
}

# # Attach our instances to the target group
resource "aws_lb_target_group_attachment" "ecom_tg_server" {
  count            = "${var.ecommerce_servers}"
  target_group_arn = "${aws_lb_target_group.ecom_tg.arn}"
  target_id        = "${element(aws_instance.spacelysprockets.*.id, count.index)}"
  port             = 80
}

# # Create a DNS record for the environment 
resource "aws_route53_record" "subdomain" {
  zone_id = "Z1BTPJJ3JDHJ7U"
  name    = "${var.subdomain}.spacelyspacesprockets.info"
  type    = "A"

  alias {
    name                   = "dualstack.${aws_lb.ecom_lb.dns_name}"
    zone_id                = "Z1H1FL5HABSF5"
    evaluate_target_health = true
  }
}
