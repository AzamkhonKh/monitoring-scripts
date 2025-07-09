# Makefile for monitoring_scripts docker test environment

.PHONY: build up down shell logs clean

build:
	docker-compose build

up:
	docker-compose up -d

e2e: build up shell

down:
	docker-compose down

shell:
	docker exec -it centos-systemd-test bash

logs:
	docker-compose logs -f

clean:
	docker-compose down -v --remove-orphans
	docker system prune -f

# Run a script inside the container, e.g. make run SCRIPT=setup_loki_stack.sh
run:
	docker exec -it centos-systemd-test bash -c "/scripts/$(SCRIPT)"
