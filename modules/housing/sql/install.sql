


CREATE TABLE IF NOT EXISTS `az_houses` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(80) NOT NULL,
  `price` INT NOT NULL DEFAULT 0,
  `interior` VARCHAR(40) NOT NULL DEFAULT 'apa_low_end',
  `locked` TINYINT NOT NULL DEFAULT 1,
  `for_sale` TINYINT NOT NULL DEFAULT 1,
  `for_rent` TINYINT NOT NULL DEFAULT 0,
  `rent_per_week` INT NOT NULL DEFAULT 0,
  `deposit` INT NOT NULL DEFAULT 0,
  `owner_identifier` VARCHAR(64) NULL,
  `owner_name` VARCHAR(80) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `az_house_doors` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `house_id` INT NOT NULL,
  `x` DOUBLE NOT NULL,
  `y` DOUBLE NOT NULL,
  `z` DOUBLE NOT NULL,
  `heading` DOUBLE NOT NULL DEFAULT 0,
  `radius` DOUBLE NOT NULL DEFAULT 2.5,
  `label` VARCHAR(80) NULL,
  PRIMARY KEY (`id`),
  KEY `idx_house_doors_house` (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `az_house_garages` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `house_id` INT NOT NULL,
  `x` DOUBLE NOT NULL,
  `y` DOUBLE NOT NULL,
  `z` DOUBLE NOT NULL,
  `heading` DOUBLE NOT NULL DEFAULT 0,
  `radius` DOUBLE NOT NULL DEFAULT 3.5,
  `label` VARCHAR(80) NULL,
  PRIMARY KEY (`id`),
  KEY `idx_house_garages_house` (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `az_house_keys` (
  `house_id` INT NOT NULL,
  `holder_identifier` VARCHAR(64) NOT NULL,
  `holder_name` VARCHAR(80) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`house_id`,`holder_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `az_house_rentals` (
  `house_id` INT NOT NULL,
  `tenant_identifier` VARCHAR(64) NULL,
  `tenant_name` VARCHAR(80) NULL,
  `rent_per_week` INT NOT NULL DEFAULT 0,
  `deposit` INT NOT NULL DEFAULT 0,
  `status` VARCHAR(20) NOT NULL DEFAULT 'listed',
  `listed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `az_house_rent_apps` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `house_id` INT NOT NULL,
  `applicant_identifier` VARCHAR(64) NOT NULL,
  `applicant_name` VARCHAR(80) NULL,
  `message` TEXT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_apps_house` (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `az_house_vehicles` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `house_id` INT NOT NULL,
  `owner_identifier` VARCHAR(64) NOT NULL,
  `plate` VARCHAR(16) NOT NULL,
  `vehicle` LONGTEXT NOT NULL,
  `stored_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_house_vehicles_house` (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `az_house_upgrades` (
  `house_id` INT NOT NULL,
  `mailbox_level` INT NOT NULL DEFAULT 0,
  `decor_level` INT NOT NULL DEFAULT 0,
  `storage_level` INT NOT NULL DEFAULT 0,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `az_house_mail` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `house_id` INT NOT NULL,
  `sender_identifier` VARCHAR(64) NULL,
  `sender_name` VARCHAR(80) NULL,
  `subject` VARCHAR(120) NOT NULL,
  `body` TEXT NOT NULL,
  `is_read` TINYINT NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_house_mail_house` (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `az_house_furniture` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `house_id` INT NOT NULL,
  `owner_identifier` VARCHAR(64) NOT NULL,
  `model` VARCHAR(80) NOT NULL,
  `x` DOUBLE NOT NULL,
  `y` DOUBLE NOT NULL,
  `z` DOUBLE NOT NULL,
  `heading` DOUBLE NOT NULL DEFAULT 0,
  `rot_x` DOUBLE NOT NULL DEFAULT 0,
  `rot_y` DOUBLE NOT NULL DEFAULT 0,
  `rot_z` DOUBLE NOT NULL DEFAULT 0,
  `meta` LONGTEXT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_house_furniture_house` (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
