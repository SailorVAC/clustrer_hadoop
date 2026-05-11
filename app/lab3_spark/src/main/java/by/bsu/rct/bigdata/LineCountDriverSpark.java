package by.bsu.rct.bigdata;

import org.apache.spark.api.java.JavaPairRDD;
import org.apache.spark.api.java.JavaRDD;
import org.apache.spark.api.java.JavaSparkContext;
import org.apache.spark.sql.SparkSession;
import scala.Tuple2;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Locale;

public class LineCountDriverSpark {

    private final SparkSession spark;

    public LineCountDriverSpark(SparkSession spark) {
        this.spark = spark;
    }

    private void runApplication(String[] args) {
        String salesPath = args[0];
        String categoriesPath = args[1];  // Второй аргумент - путь к categories.csv

        JavaSparkContext jsc = new JavaSparkContext(spark.sparkContext());

        boolean isSample = salesPath.contains("sample");

        // ===== 1. Загрузка и фильтрация продаж =====
        JavaRDD<String> salesLines = jsc.textFile(salesPath);
        JavaRDD<Tuple2<String, Tuple2<Double, String>>> salesData = salesLines
                .map(line -> {
                    String[] parts = line.split(",");
                    String date = parts[0].trim();
                    String catID = parts[2].trim();
                    double amount = Double.parseDouble(parts[4].trim());
                    return new Tuple2<>(catID, new Tuple2<>(amount, date));
                });

        // Фильтрация: 2-я декада (11-20) и дробная часть [95-99]
        JavaRDD<Tuple2<String, Tuple2<Double, String>>> filtered = salesData.filter(t -> {
            double amount = t._2()._1();
            String date = t._2()._2();
            int day = getDayOfMonth(date);

            String amountStr = String.format(Locale.ROOT, "%.2f", amount);
            String fractionalStr = amountStr.substring(amountStr.indexOf(".") + 1);
            int fractional = Integer.parseInt(fractionalStr);

            boolean validDecade = (day >= 11 && day <= 20);
            boolean validFractional = (fractional >= 95 && fractional <= 99);

            return validDecade && validFractional;
        });

        // (catID, amount)
        JavaPairRDD<String, Double> catAmount = filtered.mapToPair(t -> new Tuple2<>(t._1(), t._2()._1()));

        // Максимум по категориям
        JavaPairRDD<String, Double> maxPerCategory = catAmount.reduceByKey(Math::max);

        // ===== 2. Загрузка справочника категорий =====
        JavaRDD<String> catLines = jsc.textFile(categoriesPath);
        JavaPairRDD<String, String> catIDToName = catLines
                .mapToPair(line -> {
                    String[] parts = line.split(",");
                    return new Tuple2<>(parts[0].trim(), parts[1].trim());
                });

        // ===== 3. Join - заменяем catID на название категории =====
        JavaPairRDD<String, Tuple2<Double, String>> joined = maxPerCategory.join(catIDToName);

        // ===== 4. Формирование результата: "имя категории: максимум" =====
        JavaRDD<String> result = joined.map(t -> {
            String catName = t._2()._2();
            double maxAmount = t._2()._1();
            return catName + ": " + String.format(Locale.ROOT, "%.2f", maxAmount);
        }).sortBy(line -> line, true, 1);

        // ===== 5. Вывод или сохранение =====
        if (isSample) {
            System.out.println("=== Result (category: max amount) ===");
            result.collect().forEach(System.out::println);
        } else {
            String outputPath = "hdfs://namenode:9000/user/HUser/Work/Sudilovskiy/result_lab3";
            result.coalesce(1).saveAsTextFile(outputPath);
            System.out.println("Result saved to: " + outputPath);
        }

        jsc.close();
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            throw new Exception("Usage: <path to sales.csv> <path to categories.csv>");
        }

        SparkSession.Builder sessionBuilder = SparkSession.builder()
                .appName("Variant A - Task 2");
        if (System.getenv().containsKey("IDE_ENV")) {
            sessionBuilder.master("local[*]");
        }

        SparkSession spark = sessionBuilder.getOrCreate();

        try (spark) {
            new LineCountDriverSpark(spark).runApplication(args);
        }
    }

    private static int getDayOfMonth(String dateStr) {
        try {
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd");
            Calendar cal = Calendar.getInstance();
            cal.setTime(sdf.parse(dateStr));
            return cal.get(Calendar.DAY_OF_MONTH);
        } catch (ParseException e) {
            return -1;
        }
    }
}