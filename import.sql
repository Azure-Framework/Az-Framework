-- import.sql

CREATE TABLE IF NOT EXISTS user_vehicles (
  id INT AUTO_INCREMENT PRIMARY KEY,
  discordid VARCHAR(255) NOT NULL,
  plate      VARCHAR(20)  NOT NULL,
  model      VARCHAR(50)  NOT NULL,
  x          DOUBLE       NOT NULL,
  y          DOUBLE       NOT NULL,
  z          DOUBLE       NOT NULL,
  h          DOUBLE       NOT NULL,
  UNIQUE KEY uq_vehicle (discordid, plate),
  INDEX idx_discord (discordid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
