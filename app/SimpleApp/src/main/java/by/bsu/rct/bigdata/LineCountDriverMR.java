package by.bsu.rct.bigdata;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.conf.Configured;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.NullWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.input.TextInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.mapreduce.lib.output.TextOutputFormat;
import org.apache.hadoop.util.Tool;
import org.apache.hadoop.util.ToolRunner;
import org.apache.hadoop.fs.Path;

public class LineCountDriverMR extends Configured implements Tool {
    @Override
    public int run(String[] args) throws Exception {
        Job job = Job.getInstance(getConf(), "Line count MR App");
        job.setJarByClass(LineCountDriverMR.class);


        // TODO: Используя таблицу-подсказку, настройте Job:
        // 1. Настройте класс преобразователя (Mapper)
        job.setMapperClass(LineCountMapper.class);
        // 2. Задайте типы (Key/Value) на выходе преобразователя
        job.setMapOutputKeyClass(NullWritable.class);
        job.setMapOutputValueClass(LongWritable.class);
        // 3. Настройте класс редуктора (Reducer)
        job.setReducerClass(LineCountReducer.class);
        // 4. Задайте типы (Key/Value) на выходе приложения
        job.setOutputKeyClass(Text.class);
        job.setOutputValueClass(LongWritable.class);
        // 5. Настройте пути к файлам через FileInputFormat/FileOutputFormat
        if (args.length != 2) {
            System.err.println("Usage: LineCountDriverMR <input path> <output path>");
            System.exit(-1);
        }
        TextInputFormat.setInputPaths(job, new Path(args[0]));
        TextOutputFormat.setOutputPath(job, new Path(args[1]));

        return job.waitForCompletion(true) ? 0 : 1;
    }
    public static void main(String[] args) throws Exception {
        int res = ToolRunner.run(new Configuration(),
                new LineCountDriverMR(), args);
        System.exit(res);
    }
}