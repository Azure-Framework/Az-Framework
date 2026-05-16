
CREATE TABLE IF NOT EXISTS `daily_checkin_users` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(255) NOT NULL,
  `year` INT NOT NULL,
  `month` INT NOT NULL,
  `claimed_days` TEXT NOT NULL,
  `claimed_count` INT NOT NULL DEFAULT 0,
  `keys` INT NOT NULL DEFAULT 0,
  `last_spin` TIMESTAMP NULL DEFAULT NULL,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_user_month` (`identifier`,`year`,`month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `daily_checkin_rewards` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `month` INT NOT NULL,
  `day` INT NOT NULL,
  `money` INT DEFAULT NULL,
  `weapon` VARCHAR(100) DEFAULT NULL,
  `ammo` INT DEFAULT NULL,
  `keys` INT DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `month_day_unique` (`month`,`day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
