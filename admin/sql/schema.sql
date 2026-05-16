
CREATE TABLE IF NOT EXISTS `econ_departments` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `discordid` VARCHAR(64) NOT NULL,
  `charid` VARCHAR(64) NOT NULL,
  `department` VARCHAR(64) NOT NULL,
  `paycheck` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_discord_department` (`discordid`, `department`),
  KEY `idx_discord` (`discordid`),
  KEY `idx_department` (`department`),
  KEY `idx_charid` (`charid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
