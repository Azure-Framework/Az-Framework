ALTER TABLE `user_vehicles` ADD COLUMN `charid` varchar(64) DEFAULT NULL AFTER `discordid`;
ALTER TABLE `user_vehicles` ADD KEY `idx_user_vehicles_discordid_charid` (`discordid`,`charid`);

ALTER TABLE `user_vehicle_insurance` ADD COLUMN `charid` varchar(64) DEFAULT NULL AFTER `discordid`;
ALTER TABLE `user_vehicle_insurance` ADD KEY `idx_user_vehicle_insurance_discordid_charid` (`discordid`,`charid`);

ALTER TABLE `user_vehicle_claims` ADD COLUMN `charid` varchar(64) DEFAULT NULL AFTER `discordid`;
ALTER TABLE `user_vehicle_claims` ADD KEY `idx_user_vehicle_claims_discordid_charid` (`discordid`,`charid`);
