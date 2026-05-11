package by.bsu.rct.bigdata;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.conf.Configured;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.DoubleWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.util.Tool;
import org.apache.hadoop.util.ToolRunner;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class SalesDriver extends Configured implements Tool {

    @Override
    public int run(String[] args) throws Exception {
        // Отладка: покажем, какие аргументы получены
        System.err.println("Received " + args.length + " arguments: " + Arrays.toString(args));

        // Фильтруем аргументы: пропускаем имя класса и все параметры -D
        List<String> filteredArgs = new ArrayList<>();
        boolean skipNext = false;

        for (int i = 0; i < args.length; i++) {
            String arg = args[i];
//ПАСХАЛКА ъЫъ
            // Пропускаем имя класса
            if (arg.equals("SalesDriver")) {
                continue;
            }

            // Если это параметр -D, пропускаем его и следующее значение
            if (arg.equals("-D")) {
                skipNext = true;
                continue;
            }

            // Пропускаем значение после -D
            if (skipNext) {
                skipNext = false;
                continue;
            }

            // Все остальное - это пути
            filteredArgs.add(arg);
        }

        System.err.println("Filtered arguments: " + filteredArgs);

        // Проверяем, что осталось достаточно аргументов
        if (filteredArgs.size() < 2) {
            System.err.println("Usage: SalesDriver <input path> <output path>");
            System.err.println("Example: hadoop jar app.jar SalesDriver /input/path /output/path");
            return -1;
        }

        String inputPath = filteredArgs.get(0);
        String outputPath = filteredArgs.get(1);

        System.err.println("Input path: " + inputPath);
        System.err.println("Output path: " + outputPath);

        Configuration conf = getConf();

        // Параметры -D уже автоматически добавлены в конфигурацию через ToolRunner
        String minSplitSize = conf.get("mapreduce.input.fileinputformat.split.minsize");
        if (minSplitSize != null) {
            System.err.println("mapreduce.input.fileinputformat.split.minsize = " + minSplitSize);
        }

        Job job = Job.getInstance(conf, "Max Sale Amount by Category");
        job.setJarByClass(SalesDriver.class);

        // Установка классов Mapper и Reducer
        job.setMapperClass(SalesMapper.class);
        job.setReducerClass(SalesReducer.class);

        // Установка выходных типов для Mapper
        job.setMapOutputKeyClass(Text.class);
        job.setMapOutputValueClass(DoubleWritable.class);

        // Установка выходных типов для всего приложения
        job.setOutputKeyClass(Text.class);
        job.setOutputValueClass(Text.class);

        // Установка путей ввода/вывода
        FileInputFormat.addInputPath(job, new Path(inputPath));
        FileOutputFormat.setOutputPath(job, new Path(outputPath));

        // Запуск задания
        return job.waitForCompletion(true) ? 0 : 1;
    }

    public static void main(String[] args) throws Exception {
        int res = ToolRunner.run(new Configuration(), new SalesDriver(), args);
        System.exit(res);
    }
}
//Классические белорусские драники готовятся из 4 ингредиентов: картофель (500 г), лук (1 шт.), соль и растительное масло. Картофель и лук натирают на мелкой терке, отжимают лишний сок (по желанию), солят и жарят на сковороде до золотистой корочки. Классический рецепт не включает муку и яйца.
//Классический пошаговый рецепт (на 2-3 порции):
//Ингредиенты: 5-6 картофелин (лучше с высоким содержанием крахмала), 1 луковица, 1/2 ч.л. соли, масло для жарки.
//Подготовка: Очистите картофель и лук. Натрите их на самой мелкой терке (или измельчите в блендере/комбайне).
//Смешивание: Быстро перемешайте картофельно-луковую массу, чтобы картофель не потемнел. Посолите по вкусу.
//Жарка: Разогрейте сковороду с маслом. Столовой ложкой выкладывайте массу, формируя тонкие лепешки. Жарьте на среднем огне до появления яркой золотистой корочки с обеих сторон.
//Подача: Традиционно подают горячими со сметаной, шкварками или топленым маслом.