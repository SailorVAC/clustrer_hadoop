package by.bsu.rct.bigdata;

import org.apache.hadoop.io.DoubleWritable;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Mapper;

import java.io.IOException;
import java.time.LocalDate;

public class SalesMapper extends Mapper<LongWritable, Text, Text, DoubleWritable> {

    private final Text categoryKey = new Text();
    private final DoubleWritable amountValue = new DoubleWritable();

    @Override
    protected void map(LongWritable key, Text value, Context context)
            throws IOException, InterruptedException {

        String line = value.toString();

        if (line.startsWith("date") || line.trim().isEmpty()) {
            return;
        }

        String[] fields = line.split(",");
        if (fields.length < 5) {
            return;
        }

        String dateStr = fields[0].trim();
        String catId = fields[2].trim();
        String amountStr = fields[4].trim();

        try {
            LocalDate date = LocalDate.parse(dateStr);
            int day = date.getDayOfMonth();

            // Только 2 декада (11-20 число)
            if (day < 11 || day > 20) {
                return;
            }

            double amount = Double.parseDouble(amountStr);

            // Проверяем дробную часть через строку (самый надёжный способ)
            boolean hasValidFraction = false;
            int dotIndex = amountStr.indexOf('.');
            if (dotIndex > 0 && amountStr.length() >= dotIndex + 3) {
                // Берём первые две цифры после точки
                String twoDigits = amountStr.substring(dotIndex + 1, dotIndex + 3);
                int fractionValue = Integer.parseInt(twoDigits);
                if (fractionValue >= 95 && fractionValue <= 99) {
                    hasValidFraction = true;
                }
            }

            if (!hasValidFraction) {
                return;
            }

            categoryKey.set(catId);
            amountValue.set(amount);
            context.write(categoryKey, amountValue);

        } catch (Exception e) {
            // Игнорируем ошибки парсинга
        }
    }
}