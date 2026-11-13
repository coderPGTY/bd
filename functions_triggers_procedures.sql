USE avito_analog_db;

-- Функция get_user_rating: вычисляет средний рейтинг пользователя на основе всех отзывов на его объявления.
-- Принимает ID пользователя, возвращает число от 0.00 до 5.00.
-- Если отзывов нет — возвращает 0.00.
DELIMITER $$

CREATE FUNCTION get_user_rating(p_user_id INT) 
RETURNS DECIMAL(3,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE avg_rating DECIMAL(3,2);
    
    SELECT AVG(r.score) INTO avg_rating
    FROM Reviews r
    JOIN Advertisements a ON r.id_advertisement = a.id_advertisement
    WHERE a.id_user = p_user_id;
    
    RETURN IFNULL(avg_rating, 0.00);
END$$

DELIMITER ;

-- Функция get_active_ads_count: считает количество активных объявлений пользователя.
-- Принимает ID пользователя, возвращает целое число.
-- Активным считается объявление со статусом 1.
DELIMITER $$

CREATE FUNCTION get_active_ads_count(p_user_id INT) 
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE cnt INT;
    
    SELECT COUNT(*) INTO cnt 
    FROM Advertisements 
    WHERE id_user = p_user_id AND status = 1;
    
    RETURN cnt;
END$$

DELIMITER ;

-- Триггер trg_update_rating_after_review: срабатывает после добавления нового отзыва.
-- Автоматически пересчитывает и обновляет рейтинг продавца объявления, на которое оставлен отзыв.
-- Использует функцию get_user_rating для расчёта нового значения.
DELIMITER $$

CREATE TRIGGER trg_update_rating_after_review
AFTER INSERT ON Reviews
FOR EACH ROW
BEGIN
    DECLARE seller_id INT;
    
    SELECT id_user INTO seller_id 
    FROM Advertisements 
    WHERE id_advertisement = NEW.id_advertisement;
    
    UPDATE Users 
    SET rating = get_user_rating(seller_id)
    WHERE id_user = seller_id;
END$$

DELIMITER ;

-- Триггер trg_prevent_self_review: срабатывает перед добавлением отзыва.
-- Проверяет, не пытается ли пользователь оставить отзыв на своё собственное объявление.
-- Если автор отзыва совпадает с продавцом — блокирует операцию и выводит сообщение об ошибке.
DELIMITER $$

CREATE TRIGGER trg_prevent_self_review
BEFORE INSERT ON Reviews
FOR EACH ROW
BEGIN
    DECLARE seller_id INT;
    
    SELECT id_user INTO seller_id 
    FROM Advertisements 
    WHERE id_advertisement = NEW.id_advertisement;
    
    IF seller_id = NEW.id_author THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Нельзя оставить отзыв самому себе!';
    END IF;
END$$

DELIMITER ;

-- Процедура create_transaction: оформляет сделку покупки объявления.
-- Принимает ID объявления, ID покупателя и способ оплаты.
-- Проверяет, что объявление активно (статус 1) и что покупатель не является продавцом.
-- Создаёт запись в таблице Transactions и меняет статус объявления на "Продано" (2).
DELIMITER $$

CREATE PROCEDURE create_transaction(
    IN p_advertisement_id INT,
    IN p_buyer_id INT,
    IN p_payment_method VARCHAR(50)
)
BEGIN
    DECLARE adv_status INT;
    DECLARE seller_id INT;
    
    SELECT status, id_user INTO adv_status, seller_id
    FROM Advertisements 
    WHERE id_advertisement = p_advertisement_id;
    
    IF adv_status != 1 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Объявление не активно — нельзя оформить сделку';
    END IF;
    
    IF p_buyer_id = seller_id THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Нельзя купить своё собственное объявление';
    END IF;
    
    INSERT INTO Transactions (id_advertisement, id_buyer, payment_method)
    VALUES (p_advertisement_id, p_buyer_id, p_payment_method);
    
    UPDATE Advertisements 
    SET status = 2 
    WHERE id_advertisement = p_advertisement_id;
    
    SELECT 'Сделка успешно оформлена!' AS result;
END$$

DELIMITER ;