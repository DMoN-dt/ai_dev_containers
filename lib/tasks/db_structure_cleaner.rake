# Pg Dump заставляет создавать комментарии на Extension, а для этого нужно быть владельцем этих extension.
# Если расширение уже добавлено ранее и у пользователя нет на это прав, то schema:load падает в ошибку.
#
# Данный скрипт обёртывает эти команды для пропуска в случае нехватки прав,
# поскольку комментарий на расширении - это последнее, что может волновать в базе данных,
# особенно когда он уже создан ранее.
#
# Запускается сам в конце дампа.
#
# Если нужно запустить вручную:
#   rails -e development -r "./lib/tasks/db_structure_cleaner.rake" -e "Rake::Task['db:structure:dump'].invoke"
#
namespace :db do
  desc "Фикс второстепенных команд в db/structure.sql"
  task clean_structure: :environment do
    filename = Rails.root.join('db', 'structure.sql')
    
    if File.exist?(filename)
      # Файл создаётся в той же папке db/, что на 100% гарантирует один и тот же
      # дисковый раздел (inode) и обеспечивает полную атомарность вызова File.rename
      temp_filename = "#{filename}_mod.tmp"
      file_modified = false

      begin
        File.open(temp_filename, 'w') do |output|
          # Флаг сканирования шапки. Становится false при достижении создания таблиц/view или лимита строк
          scanning_header = true 

          # Потоковое построчное чтение. Не нагружает память независимо от размера файла
          File.foreach(filename).with_index(1) do |line, line_number|
            if scanning_header
              # Ранний выход из сканирования: регулярные выражения перестают работать 
              # после 200-й строки или при обнаружении создания первой таблицы/представления
              if line_number > 200 || line =~ /^CREATE (TABLE|VIEW) /
                scanning_header = false
              end
            end

            # Модифицируем строки только в пределах инициализации схемы (в шапке файла)
            if scanning_header && line =~ /^COMMENT ON EXTENSION ([^\s]+) IS '(.*)';$/
              ext_name = Regexp.last_match(1)
              comment_text = Regexp.last_match(2)
              file_modified = true
              
              # Оборачиваем комментарий в идемпотентный и безопасный блок PL/pgSQL
              line = <<~SQL
                DO $$
                BEGIN
                  IF NOT EXISTS (
                    SELECT 1 
                    FROM pg_description 
                    JOIN pg_extension ON pg_description.objoid = pg_extension.oid 
                    WHERE pg_extension.extname = '#{ext_name}'
                  ) THEN
                    -- Долларовые разделители $comment$ полностью изолируют любые кавычки в тексте
                    EXECUTE 'COMMENT ON EXTENSION #{ext_name} IS ' || quote_literal($comment$#{comment_text}$comment$);
                  END IF;
                EXCEPTION
                  -- Если у пользователя БД нет прав owner, то подавляем ошибку прав и успешно продолжаем загрузку схемы
                  WHEN insufficient_privilege THEN
                    NULL;
                END $$;
              SQL
            end

            # Записываем строку (модифицированную или оригинальную) во временный файл
            output.write(line)
          end
        end
        
        # Если изменения были, заменяем файл структуры новым файлом
        File.rename(temp_filename, filename) if file_modified

      ensure
        # Всегда удаляем временный файл
        File.delete(temp_filename) if File.exist?(temp_filename)
      end
    else
      puts "Предупреждение: Файл db/structure.sql не найден для фиксов."
    end
  end
end

# Связываем таски: автоматически запускаем нашу новую задачу в самом конце дампа
if defined?(Rake)
  # В Rails 7+ используется db:schema:dump, в старых версиях — db:structure:dump
  target_task = Rake::Task.task_defined?('db:structure:dump') ? 'db:structure:dump' : 'db:schema:dump'

  Rake::Task[target_task].enhance do
    # Метод invoke принудительно выполняет указанную Rake-таску
    Rake::Task['db:clean_structure'].invoke
  end
end
