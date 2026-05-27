
ALTER TABLE econ_accounts  ADD COLUMN IF NOT EXISTS charid VARCHAR(100) NOT NULL DEFAULT '' AFTER discordid;
ALTER TABLE econ_payments  ADD COLUMN IF NOT EXISTS charid VARCHAR(100) NOT NULL DEFAULT '' AFTER discordid;
ALTER TABLE econ_cards     ADD COLUMN IF NOT EXISTS charid VARCHAR(100) NOT NULL DEFAULT '' AFTER discordid;
ALTER TABLE econ_departments ADD COLUMN IF NOT EXISTS charid VARCHAR(100) NOT NULL DEFAULT '' AFTER discordid;

ALTER TABLE econ_user_money ADD COLUMN IF NOT EXISTS charid VARCHAR(100) NOT NULL DEFAULT '' AFTER discordid;



DROP TEMPORARY TABLE IF EXISTS tmp_discord_to_char;
CREATE TEMPORARY TABLE tmp_discord_to_char AS
SELECT uc.discordid, uc.charid
FROM user_characters uc
INNER JOIN (
  SELECT discordid, MIN(id) AS minid
  FROM user_characters
  GROUP BY discordid
) m ON uc.discordid = m.discordid AND uc.id = m.minid;


UPDATE econ_accounts ea
JOIN tmp_discord_to_char map ON ea.discordid = map.discordid
SET ea.charid = map.charid
WHERE ea.charid = '' OR ea.charid IS NULL;

UPDATE econ_payments p
JOIN tmp_discord_to_char map ON p.discordid = map.discordid
SET p.charid = map.charid
WHERE p.charid = '' OR p.charid IS NULL;

UPDATE econ_cards c
JOIN tmp_discord_to_char map ON c.discordid = map.discordid
SET c.charid = map.charid
WHERE c.charid = '' OR c.charid IS NULL;

UPDATE econ_departments d
JOIN tmp_discord_to_char map ON d.discordid = map.discordid
SET d.charid = map.charid
WHERE d.charid = '' OR d.charid IS NULL;


UPDATE econ_user_money eum
JOIN tmp_discord_to_char map ON eum.discordid = map.discordid
SET eum.charid = map.charid
WHERE (eum.charid = '' OR eum.charid IS NULL);


UPDATE econ_accounts SET charid = discordid WHERE charid = '' OR charid IS NULL;
UPDATE econ_payments SET charid = discordid WHERE charid = '' OR charid IS NULL;
UPDATE econ_cards SET charid = discordid WHERE charid = '' OR charid IS NULL;
UPDATE econ_departments SET charid = discordid WHERE charid = '' OR charid IS NULL;
UPDATE econ_user_money SET charid = discordid WHERE charid = '' OR charid IS NULL;


ALTER TABLE econ_accounts    ADD INDEX idx_econ_accounts_charid (charid);
ALTER TABLE econ_payments    ADD INDEX idx_econ_payments_charid (charid);
ALTER TABLE econ_cards       ADD INDEX idx_econ_cards_charid (charid);
ALTER TABLE econ_departments ADD INDEX idx_econ_departments_charid (charid);
ALTER TABLE econ_user_money  ADD INDEX idx_econ_user_money_charid (charid);




SELECT 'accounts_no_uc' AS context, COUNT(*) AS cnt FROM econ_accounts WHERE charid = discordid;
SELECT 'payments_no_uc' AS context, COUNT(*) AS cnt FROM econ_payments WHERE charid = discordid;
SELECT 'cards_no_uc' AS context, COUNT(*) AS cnt FROM econ_cards WHERE charid = discordid;
SELECT 'departments_no_uc' AS context, COUNT(*) AS cnt FROM econ_departments WHERE charid = discordid;


SELECT charid, COUNT(*) AS cnt
FROM econ_user_money
GROUP BY charid
HAVING COUNT(*) > 1
ORDER BY cnt DESC;


SELECT charid, COUNT(*) AS cnt FROM econ_accounts GROUP BY charid HAVING COUNT(*) > 10 ORDER BY cnt DESC LIMIT 50;
SELECT charid, COUNT(*) AS cnt FROM econ_payments GROUP BY charid HAVING COUNT(*) > 10 ORDER BY cnt DESC LIMIT 50;


DROP TEMPORARY TABLE IF EXISTS tmp_discord_to_char;

CREATE TABLE IF NOT EXISTS `econ_investments` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `discordid` varchar(64) DEFAULT '',
  `charid` varchar(100) NOT NULL,
  `plan_code` varchar(32) NOT NULL,
  `plan_name` varchar(100) NOT NULL,
  `risk` varchar(24) NOT NULL DEFAULT 'Low',
  `return_rate` DECIMAL(8,2) NOT NULL DEFAULT 0.00,
  `principal` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  `payout` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  `status` ENUM('active','closed') NOT NULL DEFAULT 'active',
  `notes` varchar(255) DEFAULT '',
  `started_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `matures_at` DATETIME NOT NULL,
  `closed_at` DATETIME NULL DEFAULT NULL,
  INDEX idx_econ_investments_charid (`charid`),
  INDEX idx_econ_investments_status (`status`),
  INDEX idx_econ_investments_matures (`matures_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
