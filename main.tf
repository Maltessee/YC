
locals {
  cloud        = "cloud"
  folder       = "folder"
  vm_user      = "s1s"
  ssh_key_path = "s1s.pub"
  domain       = "terramorf.ru"
  tkn          = file("token.txt")
}

terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.13.0"
    }
  }
}

provider "yandex" {
  token     = local.tkn
  cloud_id  = local.cloud
  folder_id = local.folder
  zone      = "ru-central1-a"
}

resource "yandex_iam_service_account" "albsa" {
  name = "albsa"
}

resource "yandex_resourcemanager_folder_iam_member" "editor" {
  folder_id = local.folder
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.albsa.id}"
}

resource "yandex_vpc_network" "net" {
  name = "net"
}

resource "yandex_vpc_subnet" "subneta" {
  name           = "subneta"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["192.168.1.0/24"]
}

resource "yandex_vpc_subnet" "subnetb" {
  name           = "subnetb"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["192.168.2.0/24"]
}

resource "yandex_vpc_subnet" "subnetd" {
  name           = "subnetd"
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["192.168.3.0/24"]
}

resource "yandex_vpc_security_group" "alb-sg" {
  description = "Security group for ALB tasks"
  name        = "alb-sg"
  network_id  = yandex_vpc_network.net.id

  egress {
    protocol       = "ANY"
    description    = "any"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 1
    to_port        = 65535
  }

  ingress {
    protocol       = "TCP"
    description    = "ext-http"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "ext-https"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  ingress {
    protocol          = "TCP"
    description       = "healthchecks"
    predefined_target = "loadbalancer_healthchecks"
    port              = 30080
  }
}


resource "yandex_compute_instance_group" "ig-vm-zonnea" {
  name               = "ig-vm-zonnea"
  folder_id          = local.folder
  service_account_id = yandex_iam_service_account.albsa.id
  instance_template {
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.albsa.id
    resources {
      cores         = 2
      core_fraction = 5
      memory        = 2

    }

    boot_disk {
      initialize_params {
        image_id = "image"
        type     = "network-hdd"
        size     = 18
      }
    }

    network_interface {
      network_id = yandex_vpc_network.net.id
      subnet_ids = [yandex_vpc_subnet.subneta.id, yandex_vpc_subnet.subnetb.id, yandex_vpc_subnet.subnetd.id]
      nat        = true
    }

    metadata = {
      ssh-keys = "s1s:${file("s1s.pub")}"
    }
  }

  scale_policy {
    fixed_scale {
      size = 3
    }
  }

  allocation_policy {
    zones = ["ru-central1-a", "ru-central1-b", "ru-central1-d"]
  }

  deploy_policy {
    max_unavailable = 1
    max_expansion   = 0
  }

  application_load_balancer {
    target_group_name = "tg-zonnea"
  }
}

resource "yandex_compute_instance_group" "ig-vm-zonneb" {
  name               = "ig-vm-zonneb"
  folder_id          = local.folder
  service_account_id = yandex_iam_service_account.albsa.id
  instance_template {
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.albsa.id
    resources {
      cores         = 2
      core_fraction = 5
      memory        = 2

    }

    boot_disk {
      initialize_params {
        image_id = "image"
        type     = "network-hdd"
        size     = 18
      }
    }

    network_interface {
      network_id = yandex_vpc_network.net.id
      subnet_ids = [yandex_vpc_subnet.subneta.id, yandex_vpc_subnet.subnetb.id, yandex_vpc_subnet.subnetd.id]
      nat        = true
    }

    metadata = {
      ssh-keys = "s1s:${file("s1s.pub")}"
    }
  }

  scale_policy {
    fixed_scale {
      size = 3
    }
  }

  allocation_policy {
    zones = ["ru-central1-a", "ru-central1-b", "ru-central1-d"]
  }

  deploy_policy {
    max_unavailable = 1
    max_expansion   = 0
  }

  application_load_balancer {
    target_group_name = "tg-zonneb"
  }
}

resource "yandex_alb_backend_group" "bg-zonnea" {
  name = "bg-zonnea"

  http_backend {
    name             = "backend-zonnea"
    port             = 80
    target_group_ids = [yandex_compute_instance_group.ig-vm-zonnea.application_load_balancer.0.target_group_id]
    healthcheck {
      timeout          = "10s"
      interval         = "2s"
      healthcheck_port = 80
      http_healthcheck {
        path = "/"
      }
    }
  }
}

resource "yandex_alb_backend_group" "bg-zonneb" {
  name = "bg-zonneb"

  http_backend {
    name             = "backend-zonneb"
    port             = 80
    target_group_ids = [yandex_compute_instance_group.ig-vm-zonneb.application_load_balancer.0.target_group_id]
    healthcheck {
      timeout          = "10s"
      interval         = "2s"
      healthcheck_port = 80
      http_healthcheck {
        path = "/"
      }
    }
  }
}


resource "yandex_alb_http_router" "http-router" {
  name = "http-router"
}

resource "yandex_alb_virtual_host" "alb-host" {
  name           = "alb-host"
  http_router_id = yandex_alb_http_router.http-router.id
  route {
    name = "p1-wiki"
    http_route {
      http_match {
        path {
          prefix = "/wiki"
        }
      }
      http_route_action {
        backend_group_id = yandex_alb_backend_group.bg-zonnea.id
      }
    }
  }
  route {
    name = "p2-member"
    http_route {
      http_match {
        path {
          prefix = "/member"
        }
      }
      http_route_action {
        backend_group_id = yandex_alb_backend_group.bg-zonneb.id
      }
    }
  }
  route {
    name = "p3-default"
    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.bg-zonnea.id
      }
    }
  }
}


resource "yandex_alb_load_balancer" "alb" {
  name               = "alb"
  network_id         = yandex_vpc_network.net.id
  security_group_ids = [yandex_vpc_security_group.alb-sg.id]

  allocation_policy {
    location {
      zone_id   = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.subneta.id
    }

    location {
      zone_id   = "ru-central1-b"
      subnet_id = yandex_vpc_subnet.subnetb.id
    }

    location {
      zone_id   = "ru-central1-d"
      subnet_id = yandex_vpc_subnet.subnetd.id
    }
  }

  listener {
    name = "alb-listener"
    endpoint {
      address {
        external_ipv4_address {
        }
      }
      ports = [80]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.http-router.id
      }
    }
  }
}

resource "yandex_dns_zone" "alb-zone" {
  name        = "alb-zone"
  description = "Public zone"
  zone        = "${local.domain}."
  public      = true
}

resource "yandex_dns_recordset" "rs-1" {
  zone_id = yandex_dns_zone.alb-zone.id
  name    = "${local.domain}."
  ttl     = 600
  type    = "A"
  data    = [yandex_alb_load_balancer.alb.listener[0].endpoint[0].address[0].external_ipv4_address[0].address]
}

resource "yandex_dns_recordset" "rs-2" {
  zone_id = yandex_dns_zone.alb-zone.id
  name    = "www"
  ttl     = 600
  type    = "CNAME"
  data    = [local.domain]
}
