package by.bsu.rct.bigdata;

import org.apache.hadoop.io.DoubleWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Reducer;

import java.io.IOException;
import java.util.Locale;

public class SalesReducer extends Reducer<Text, DoubleWritable, Text, Text> {

    private final Text resultValue = new Text();

    @Override
    protected void reduce(Text key, Iterable<DoubleWritable> values, Context context)
            throws IOException, InterruptedException {

        double maxAmount = Double.MIN_VALUE;

        for (DoubleWritable val : values) {
            double amount = val.get();
            if (amount > maxAmount) {
                maxAmount = amount;
            }
        }

        // Форматируем вывод: максимум с 2 цифрами в дробной части, разделитель – точка
        // Используем Locale.ROOT для гарантии использования точки
        String formattedMax = String.format(Locale.ROOT, "%.2f", maxAmount);
        resultValue.set(formattedMax);

        context.write(key, resultValue);
    }
}